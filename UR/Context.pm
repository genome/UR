package UR::Context;

use strict;
use warnings;
use Date::Parse;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Context',    
    english_name => 'ur context',
    is_abstract => 1,
    doc => 'Represents the composite state of all objects in a given context.  May be the defaykt base context, an alternate base context, or a transaction context.',
);

# This will eventually just point to the current context object, 
# and will change when the context changes, but for now everything will work as a class method
$UR::Context::current = __PACKAGE__;

our $all_objects_loaded ||= {};               # Master index of all tracked objects by class and then id.
our $all_change_subscriptions ||= {};         # Index of other properties by class, property_name, and then value.
our $all_objects_are_loaded ||= {};           # Track when a class informs us that all objects which exist are loaded.
our $all_params_loaded ||= {};                # Track parameters used to load by class then _param_key

sub get_default_data_source {
    # TODO: a context should be able to specify a specific place to go for general data.
    # This is used only to get things like the system time, etc.
    my @ds = UR::DataSource->is_loaded();
    return $ds[0];
}

# the base context is the root snapshot of reality the application is using
# it only varies when we flip to development/testing etc.

sub get_base {
    shift;
    UR::Context::Base->get_current(@_);
}

sub set_base {
    shift;
    UR::Context::Base->set_current(@_);
}

# the process context is the perspective on the data from the current process/thread
# this is primarily for buffering, when the process is the current process

sub get_process {
    shift;
    UR::Context::Process->get_current(@_);
}

# the current context is either the process context, or the current transaction on-top of it

sub get_current {
    my $context;
    
    $context = $UR::Context::Transaction::open_transaction_stack[-1];
    return $context if $context;
    
    $context = UR::Context::Process->get_current();
    return $context if $context;
    
    $context = UR::Context::Base->get_current();
    return $context if $context;
    
    return;
}

sub send_email {
    my $self = shift;
    my $base = $self->get_base;
    $base->_send_email(@_);
}

# this is used to determine which data source/sources to use for loading objects matching a given rule

our $data_source_mapping = {};

sub set_data_sources {
    my $self = shift;
#print "In set_data_sources\n";
#$DB::single=1;
    while (my $class_name = shift) {
        my $data_source_detail = shift;
        unless (ref($data_source_detail) eq 'HASH') {
        #if ($data_source_detail->isa("UR::DataSource")) {
            my $boolexpr = UR::BoolExpr->resolve_for_class_and_params($class_name,());
            $data_source_detail = 
                { data_source => $data_source_detail, boolexpr_id => $boolexpr->id },    
            ;
        }
        my $ds_list = $data_source_mapping->{$class_name} ||= [];
        push @$ds_list, $data_source_detail;
    } 
}

sub resolve_data_sources_for_class_meta_and_rule {
    my $self = shift;
    my $class_meta = shift;
    my $boolexpr = shift;  ## ignored in the default case    

#print "in resolve_data_sources_for_class_meta_and_rule for class meta ".$class_meta->class_name."\n";
    my $class_name = $class_meta->class_name;
#$DB::single=1;

    # These are some hard-coded cases for splitting up class-classes
    # and data dictionary entities into namespace-specific meta DBs.
    # Maybe there's some more generic way to move this somewhere else

    # FIXME This part is commented out for the moment.  When class info is in the 
    # Meta DBs, then try getting this to work
    #if ($class_name eq 'UR::Object::Type') {
    #    my %params = $boolexpr->legacy_params_hash;
    #    my($namespace) = ($params->{'class_name'} =~ m/^(\w+?)::/);
    #    $namespace ||= $params->{'class_name'};  # In case the class name is just the namespace
    #    
    #    return $namespace . '::DataSource::Meta';
    #}


    if (my $mapping = $data_source_mapping->{$class_name}) {
        my $class_name = $boolexpr->subject_class_name;
        for my $possible_ds_data (@$mapping) {
            #my $ds_boolexpr_id = $possible_ds_data->{boolexpr_id};
            #my $ds_boolexpr = UR::BoolExpr->get($ds_boolexpr_id);
            #if ($boolexpr->might_overlap($ds_boolexpr)) {
                return $possible_ds_data->{data_source};
            #}
        }

    # For data dictionary items
    } elsif ($class_name =~ m/^UR::DataSource::RDBMS::(.*)/) {
        if (!defined $boolexpr) {
            $DB::single=1;
        }

        my $params = $boolexpr->legacy_params_hash;
        if ($params->{'namespace'}) {
            return $params->{'namespace'} . '::DataSource::Meta';

        } elsif ($params->{'data_source'} &&
                 ! ref($params->{'data_source'}) &&
                 $params->{'data_source'}->can('get_namespace')) {

            my $namespace = $params->{'data_source'}->get_namespace;
            return $namespace . '::DataSource::Meta';

        } elsif ($params->{'data_source'} &&
                 ref($params->{'data_source'}) eq 'ARRAY') {
            my %namespaces = map { $_->get_namespace => 1 } @{$params->{'data_source'}};
            unless (scalar(keys %namespaces) == 1) {
                Carp::confess("get() across multiple namespaces is not supported");
            }
            my $namespace = $params->{'data_source'}->[0]->get_namespace;
            return $namespace . '::DataSource::Meta';
        } else {
            Carp::confess("Required parameter (namespace or data_source) missing");
            #return 'UR::DataSource::Meta';
        }

    } else {
        return $class_meta->data_source;
    }
}

# this is used to determine which data source an object should be saved-to

sub resolve_data_source_for_object {
    my $self = shift;
    my $object = shift;
#print "in resolve_data_source_for_object for a ",$object->get_class_object->class_name,"\n";
#$DB::single=1;
    my $class_meta = $object->get_class_object;
    
    # FIXME this pattern match is going to get called a lot.
    # Make up something that's faster to do the job
    if ($class_meta->class_name =~ m/^UR::DataSource::RDBMS::/) {
        my $data_source = $object->data_source;
        my($namespace) = ($data_source =~ m/(^\w+?)::DataSource/);
        return $namespace . '::DataSource::Meta';
    }
        
    my $ds = $class_meta->data_source;
    return $ds;
}

# this turns on and off light caching (weak refs)

sub _light_cache {
    if (@_ > 1) {
        $UR::Context::light_cache = $_[1];
    }
    return $UR::Context::light_cache;
}


# this is the underlying method for get/load/is_loaded in ::Object

sub get_objects_for_class_and_rule {
    my ($self, $class, $rule, $load, $return_closure) = @_;

    #my @params = $rule->params_list;
    #print "GET: $class @params\n";

    # this is a no-op if the rule is already normalized
    my $normalized_rule = $rule->get_normalized_rule_equivalent;
    
    # if $load is undefined, and there is no underlying context, we define it to FALSE explicitly
    my $meta = $class->get_class_object();    
    my $id_property_sorter = $meta->id_property_sorter;
    my ($ds) = $self->resolve_data_sources_for_class_meta_and_rule($meta,$rule);
    unless ($ds) {
        $load = 0;
    }
    
    # this is an arrayref of all of the cached data
    my $cached;
    
    # see if we need to load if load was not defined
    unless (defined $load) {
        # check to see if the cache is complete
        # also returns a list of the complete cached objects where that list is found as a side-effect
        my ($cache_is_complete, $cached) = $self->_cache_is_complete_for_class_and_normalized_rule($class, $normalized_rule);
        $load = ($cache_is_complete ? 0 : 1);
    }

    # optimize
    if (!$load and !$return_closure) {
        #print "shortcutting out\n";
        my @c = $self->_get_objects_for_class_and_rule_from_cache($class,$normalized_rule);
        return @c if wantarray;
        Carp::confess("multiple objects found for a call in scalar context!  Using " . __PACKAGE__) if @c > 1;
        return $c[0];
    }

    
    # the above process might have found all of the cached data required as a side-effect in which case we have a value for this early (ugly but DRY)
    # either way: ensure the cached data is known and sorted
    if ($cached) {
        @$cached = sort $id_property_sorter @$cached;
    }
    else {
        $cached = [ sort $id_property_sorter $self->_get_objects_for_class_and_rule_from_cache($class,$normalized_rule) ];
    }
    
    
    # make a loading iterator if loading must be done for this rule
    my $loading_iterator;
    if ($load) {
        
        # this returns objects from the underlying context after importing them into the current context
        my $underlying_context_closure = $self->_create_import_iterator_for_underlying_context($normalized_rule,$ds);
        
        # this will interleave the above with any data already present in the current context
        $loading_iterator = sub {
            my ($next_obj_current_context) = shift @$cached;
            my ($next_obj_underlying_context) = $underlying_context_closure->(1) if $underlying_context_closure;
            if (!$next_obj_underlying_context) {
                $underlying_context_closure = undef;
            }
            
            # decide which pending object to return next
            # both the cached list and the list from the database are sorted separately,
            # we're merging these into one return stream here
            my $comparison_result;
            if ($next_obj_underlying_context && $next_obj_current_context) {
                $comparison_result = $id_property_sorter->($next_obj_underlying_context, $next_obj_current_context);
            }
            
            my $next_object;
            if (
                $next_obj_underlying_context 
                and $next_obj_current_context 
                and $comparison_result == 0 # $next_obj_underlying_context->id eq $next_obj_current_context->id
            ) {
                # the database and the cache have the same object "next"
                $next_object = $next_obj_current_context;
                $next_obj_current_context = undef;
                $next_obj_underlying_context = undef;
            }
            elsif (                
                $next_obj_underlying_context
                and (
                    (!$next_obj_current_context)
                    or
                    ($comparison_result < 0) # ($next_obj_underlying_context->id le $next_obj_current_context->id) 
                )
            ) {
                # db object is next to be returned
                $next_object = $next_obj_underlying_context;
                $next_obj_underlying_context = undef;
            }
            elsif (                
                $next_obj_current_context 
                and (
                    (!$next_obj_underlying_context)
                    or 
                    ($comparison_result > 0) # ($next_obj_underlying_context->id ge $next_obj_current_context->id) 
                )
            ) {
                # cached object is next to be returned
                $next_object = $next_obj_current_context;
                $next_obj_current_context = undef;
            }
            
            return unless defined $next_object;
            return $next_object;
        };
    }
    
    if ($return_closure) {
        if ($load) {
            # return the iterator made above
            return $loading_iterator;
        }
        else {
            # make a quick iterator for the cached data
            return sub { return shift @$cached };
        }
    }
    else {
        my @results;
        if ($loading_iterator) {
            # use the iterator made above
            my $found;
            while ($found = $loading_iterator->(1)) {        
                push @results, $found;
            }
        }
        else {
            # just get the cached data
            @results = @$cached;
        }
        return unless defined wantarray;
        return @results if wantarray;
        if (@results > 1) {
            die "Multiple results unexpected for query:"
                . Data::Dumper::Dumper(\@results,$rule->subject_class_name,[$rule->params_list]);
        }
        return $results[0];
    }
}

sub _create_import_iterator_for_underlying_context {

    my ($self, $rule, $dsx) = @_; 

    my ($rule_template, @values) = $rule->get_rule_template_and_values();    
    my $template_data = $dsx->_get_template_data_for_loading($rule_template); 

    #
    # the template has general class data
    #

    my $ghost_class                                 = $template_data->{ghost_class};
    my $class_name                                  = $template_data->{class_name};
    my $class = $class_name;

    my @parent_class_objects                        = @{ $template_data->{parent_class_objects} };
    my @all_table_properties                        = @{ $template_data->{all_table_properties} };
    my $first_table_name                            = $template_data->{first_table_name};
    my $sub_classification_meta_class_name          = $template_data->{sub_classification_meta_class_name};
    my $sub_classification_property_name            = $template_data->{sub_classification_property_name};
    my $sub_classification_method_name              = $template_data->{sub_classification_method_name};

    my @all_id_property_names                       = @{ $template_data->{all_id_property_names} };           
    my @id_properties                               = @{ $template_data->{id_properties} };               
    my $id_property_sorter                          = $template_data->{id_property_sorter};                    
    
    my $sub_typing_property                         = $template_data->{sub_typing_property};
    my $class_table_name                            = $template_data->{class_table_name};
    my @type_names_under_class_with_no_table        = @{ $template_data->{type_names_under_class_with_no_table} };

    #
    # the template has explicit template data
    #  
    
    my @property_names_in_resultset_order           = @{ $template_data->{property_names_in_resultset_order} };
    my $properties_for_params                       = $template_data->{properties_for_params};
    
    my $rule_template_id                            = $template_data->{rule_template_id};
    my $rule_template_without_recursion_desc        = $template_data->{rule_template_without_recursion_desc};
    my $rule_template_id_without_recursion_desc     = $template_data->{rule_template_id_without_recursion_desc};
    my $rule_matches_all                            = $template_data->{rule_matches_all};
    my $rule_template_is_id_only                    = $template_data->{rule_template_is_id_only};
    my $rule_specifies_id                           = $template_data->{rule_specifies_id};
    my $rule_template_specifies_value_for_subtype   = $template_data->{rule_template_specifies_value_for_subtype};

    my $recursion_desc                              = $template_data->{recursion_desc};
    my $recurse_property_on_this_row                = $template_data->{recurse_property_on_this_row};
    my $recurse_property_referencing_other_rows     = $template_data->{recurse_property_referencing_other_rows};

    my $needs_further_boolexpr_evaluation_after_loading = $template_data->{'needs_further_boolexpr_evaluation_after_loading'};

    #
    # if there is a property which specifies a sub-class for the objects, switch rule/values and call this again recursively
    #

    if (my $sub_typing_property) {
        warn "Implement me carefully";
        if ($rule_template_specifies_value_for_subtype) {
            $DB::single = 1;           
            my @values = @_;
            my $rule = $rule_template->get_rule_for_values(@values);
            my $value = $rule->specified_value_for_property_name($sub_typing_property);
            my $type_obj = $sub_classification_meta_class_name->get($value);
            if ($type_obj) {
                my $subclass_name = $type_obj->subclass_name($class);
                if ($subclass_name and $subclass_name ne $class) {
                    $rule = $subclass_name->get_rule_for_params($rule->params_list, $sub_typing_property => $value);
                    return $self->create_iterator_closure_for_rule($rule,$dsx);
                }
            }
            else {
                die "No $value for $class?\n";
            }
        }
        elsif (not $class_table_name) {
            $DB::single = 1;
            # we're in a sub-class, and don't have the type specified
            # check to make sure we have a table, and if not add to the filter
            my $rule = $class_name->get_rule_for_params(
                $rule_template->get_rule_for_values(@values)->params_list, 
                $sub_typing_property => (@type_names_under_class_with_no_table > 1 ? \@type_names_under_class_with_no_table : $type_names_under_class_with_no_table[0]),
            );
            return $self->create_iterator_closure_for_rule($rule,$dsx)
        }
        else {
            # continue normally
            # the logic below will handle sub-classifying each returned entity
        }
    }

    # gather the data specific to this group of values
    # we don't cache these on the rule since a rule is typically only loaded once anyway

    my $rule_id = $rule->id;    
    my $rule_without_recursion_desc = $rule_template_without_recursion_desc->get_rule_for_values(@values);    
    my $id = $rule->specified_value_for_id;
        
    # the iterator may need subordinate iterators if the objects are subclassable
    my %subclass_is_safe_for_re_bless;
    my %subclass_for_subtype_name;  
    my %subordinate_rule_template_for_class;
    my %subordinate_iterator_for_class;
    my %recurse_property_value_found;

    # buffers for the iterator
    my $next_object;
    my $pending_db_object;
    my $pending_db_object_data;
    my $pending_cached_object;
    my $next_db_row;
    my $object;
    my $rows = 0;       # number of rows the query returned

    # make an iterator for the data source, and wrap it
    my $db_iterator = $dsx->create_iterator_closure_for_rule($rule);

    my $iterator = sub {
        # This is the number of items we're expected to return.
        # It is 1 by default for iterators, and -1 for a basic get() which returns everything.
        my $countdown = $_[0] || 1;
        
        my @return_objects;
        
        while ($countdown != 0) {
            # This block is necessary because Perl only looks 2 levels up for closure pad members.
            # It ensures the above variables hold their value in this closure
            no warnings;
            (
                $dsx, 
                $rule_template, 
                @values,
                $template_data,
                $ghost_class,
                $class_name,
                $class,
                @parent_class_objects,
                @all_table_properties,
                $first_table_name,
                $sub_classification_meta_class_name,
                $sub_classification_property_name,
                $sub_classification_method_name,
                @all_id_property_names,
                @id_properties,
                $id_property_sorter,
                $sub_typing_property,
                $class_table_name,
                @type_names_under_class_with_no_table,
                $recursion_desc,
                $recurse_property_on_this_row,
                $recurse_property_referencing_other_rows,
                $properties_for_params,
                @property_names_in_resultset_order,
                $rule_template_id,
                $rule_template_without_recursion_desc,
                $rule_template_id_without_recursion_desc,
                $rule_matches_all,
                $rule_template_is_id_only,
                $rule_template_specifies_value_for_subtype,
                $rule_specifies_id,
                $rule,
                $rule_id,
                $rule_without_recursion_desc,
                %recurse_property_value_found,
                $id,
                %subclass_is_safe_for_re_bless,
                %subordinate_rule_template_for_class,
                %subordinate_iterator_for_class,
                $next_object,
                $pending_db_object,
                $object,
                $rows,
                %subclass_for_subtype_name,
                $needs_further_boolexpr_evaluation_after_loading,
            );
            use warnings;

            # this loop will redo when the data returned no longer matches the rule in the current STM
            for (1) {
                $pending_db_object = undef;

                my ($pending_db_object_data) = $db_iterator->();                
                unless ($pending_db_object_data) {
                    if ($rows == 0) {
                        # if we got no data at all from the sql then we give a status
                        # message about it and we update all_params_loaded to indicate
                        # that this set of parameters yielded 0 objects
                        
                        if ($rule_template_is_id_only) {
                            $UR::Object::all_objects_loaded->{$class}->{$id} = undef;
                        }
                        else {
                            $UR::Object::all_params_loaded->{$class}->{$rule_id} = 0;
                        }
                    }
                    
                    if ( $rule_matches_all ) {
                        # No parameters.  We loaded the whole class.
                        # Doing a load w/o a specific ID w/o custom SQL loads the whole class.
                        # Set a flag so that certain optimizations can be made, such as 
                        # short-circuiting future loads of this class.        
                        $class->all_objects_are_loaded(1);        
                    }
                    
                    if ($recursion_desc) {
                        my @results = $class->is_loaded($rule_without_recursion_desc);
                        $UR::Object::all_params_loaded->{$class}{$rule_without_recursion_desc->id} = scalar(@results);
                        for my $object (@results) {
                            $object->{load}{param_key}{$class}{$rule_without_recursion_desc->id}++;
                        }
                    }
                    last;
                }
                
                # we count rows processed mainly for more concise sanity checking
                $rows++;
               
                # resolve id
                my $pending_db_object_id = (@id_properties > 1)
                    ? $class->composite_id(@{$pending_db_object_data}{@id_properties})
                    : $pending_db_object_data->{$id_properties[0]};                
                unless (defined $pending_db_object_id) {
                    Carp::confess(
                        "no id found in object data?\n" 
                        . Data::Dumper::Dumper($pending_db_object_data, \@id_properties)
                    );
                }
            
                # skip if this object has been deleted but not committed
                # TODO: MOVE
                do {
                    no warnings;
                    if ($UR::Object::all_objects_loaded->{$ghost_class}{$pending_db_object_id}) {
                        $pending_db_object = undef;
                        redo;
                    }
                };

                # ensure that we're not remaking things which have already been loaded
                # TODO: MOVE
                if ($pending_db_object = $UR::Object::all_objects_loaded->{$class}{$pending_db_object_id}) {
                    # The object already exists.            
                    my $dbsu = $pending_db_object->{db_saved_uncommitted};
                    my $dbc = $pending_db_object->{db_committed};
                    if ($dbsu) {
                        # Update its db_saved_uncommitted snapshot.
                        %$dbsu = (%$dbsu, %$pending_db_object_data);
                    }
                    elsif ($dbc) {
                        # only go over property names as a joined query may pull back columns that
                        # are not properties (e.g. find DNA for PSE ID 1001 would get PSE attributes in the query)
                        for my $property ($class->property_names) {
                            no warnings;
                            if ($pending_db_object_data->{$property} ne $dbc->{$property}) {
                                # This has changed in the database since we loaded the object.
                                
                                # Ensure that none of the outside changes conflict with 
                                # any inside changes, then apply the outside changes.
                                if ($pending_db_object->{$property} eq $dbc->{$property}) {
                                    # no changes to this property in the application
                                    # update the underlying db_committed
                                    $dbc->{$property} = $pending_db_object_data->{$property};
                                    # update the regular state of the object in the application
                                    $pending_db_object->$property($pending_db_object_data->{$property}); 
                                }
                                else {
                                    # conflicting change!
                                    Carp::confess(qq/
                                        A change has occurred in the database for
                                        $class property $property on object $pending_db_object->{id}
                                        from '$dbc->{$property}' to '$pending_db_object_data->{$property}'.                                    
                                        At the same time, this application has made a change to 
                                        that value to $pending_db_object->{$property}.
            
                                        The application should lock data which it will update 
                                        and might be updated by other applications. 
                                    /);
                                }
                            }
                        }
                        # Update its db_committed snapshot.
                        %$dbc = (%$dbc, %$pending_db_object_data);
                    }
                    
                    if ($dbc || $dbsu) {
                        $dsx->debug_message("object was already loaded", 4);
                    }
                    else {
                        # No db_committed key.  This object was "create"ed 
                        # even though it existed in the database, and now 
                        # we've tried to load it.  Raise an error.
                        die "$class $pending_db_object_id has just been loaded, but it exists in the application as a new unsaved object!\n" . Dumper($pending_db_object) . "\n";
                    }
                    
                    unless ($rule_without_recursion_desc->evaluate($pending_db_object)) {
                        # The object is changed in memory and no longer matches the query rule (= where clause)
                        unless ($rule_specifies_id) {
                            $pending_db_object->{load}{param_key}{$class}{$rule_id}++;
                            $UR::Object::all_params_loaded->{$class}{$rule_id}++;                    
                        }
                        $pending_db_object->signal_change('load');                        
                        $pending_db_object = undef;
                        redo;
                    }
                    
                } # end handling objects which are already loaded
                else {        
                    # create a new object for the resultset row
                    $pending_db_object = bless { %$pending_db_object_data, id => $pending_db_object_id }, $class;
                    $pending_db_object->{db_committed} = $pending_db_object_data;    
                    
                    # determine the subclass name for classes which automatically sub-classify
                    my $subclass_name;
                    if (    
                            ($sub_classification_meta_class_name or $sub_classification_method_name)
                            and                                    
                            (ref($pending_db_object) eq $class) # not already subclased  
                    ) {
                        if ($sub_classification_method_name) {
                            $subclass_name = $class->$sub_classification_method_name($pending_db_object);
                            unless ($subclass_name) {
                                Carp::confess(
                                    "Failed to sub-classify $class using method " 
                                    . $sub_classification_method_name
                                );
                            }        
                        }
                        else {    
                            #$DB::single = 1;
                            # Group objects requiring reclassification by type, 
                            # and catch anything which doesn't need reclassification.
                            
                            my $subtype_name = $pending_db_object->$sub_classification_property_name;
                            
                            $subclass_name = $subclass_for_subtype_name{$subtype_name};
                            unless ($subclass_name) {
                                my $type_obj = $sub_classification_meta_class_name->get($subtype_name);
                                
                                unless ($type_obj) {
                                    # The base type may give the final subclass, or an intermediate
                                    # either choice has trade-offs, but we support both.
                                    # If an intermediate subclass is specified, that subclass
                                    # will join to a table with another field to indicate additional 
                                    # subclassing.  This means we have to do this part the hard way.
                                    # TODO: handle more than one level.
                                    my @all_type_objects = $sub_classification_meta_class_name->get();
                                    for my $some_type_obj (@all_type_objects) {
                                        my $some_subclass_name = $some_type_obj->subclass_name($class);
                                        unless (UR::Object::Type->get($some_subclass_name)->is_abstract) {
                                            next;
                                        }                
                                        my $some_subclass_meta = $some_subclass_name->get_class_object;
                                        my $some_subclass_type_class = 
                                                        $some_subclass_meta->sub_classification_meta_class_name;
                                        if ($type_obj = $some_subclass_type_class->get($subtype_name)) {
                                            # this second-tier subclass works
                                            last;
                                        }       
                                        else {
                                            # try another subclass, and check the subclasses under it
                                            print "skipping $some_subclass_name: no $subtype_name for $some_subclass_type_class\n";
                                        }
                                        print "";
                                    }
                                }
                                
                                if ($type_obj) {                
                                    $subclass_name = $type_obj->subclass_name($class);
                                }
                                else {
                                    warn "Failed to find $class_name sub-class for type '$subtype_name'!";
                                    $subclass_name = $class_name;
                                }
                                
                                unless ($subclass_name) {
                                    Carp::confess(
                                        "Failed to sub-classify $class using " 
                                        . $type_obj->class
                                        . " '" . $type_obj->id . "'"
                                    );
                                }        
                                
                                $subclass_name->class;
                            }
                            $subclass_for_subtype_name{$subtype_name} = $subclass_name;
                        }
                        
                        unless ($subclass_name->isa($class)) {
                            # We may have done a load on the base class, and not been able to use properties to narrow down to the correct subtype.
                            # The resultset returned more data than we needed, and we're filtering out the other subclasses here.
                            $pending_db_object = undef;
                            redo; 
                        }
                    }
                    else {
                        # regular, non-subclassifier
                        $subclass_name = $class;
                    }
                    
                    # store the object
                    # note that we do this on the base class even if we know it's going to be put into a subclass below
                    # TODO: MOVE
                    $UR::Object::all_objects_loaded->{$class}{$pending_db_object_id} = $pending_db_object;
                    #$pending_db_object->signal_change('create_object', $pending_db_object_id);                        
                    
                    # If we're using a light cache, weaken the reference.
                    # TODO: MOVE
                    if ($UR::Context::light_cache and substr($class,0,5) ne 'App::') {
                        Scalar::Util::weaken($UR::Object::all_objects_loaded->{$class_name}->{$pending_db_object_id});
                    }
                    
                    # TODO: MOVE
                    unless ($rule_specifies_id) {
                        $pending_db_object->{load}{param_key}{$class}{$rule_id}++;
                        $UR::Object::all_params_loaded->{$class}{$rule_id}++;    
                    }
                    
                    unless ($subclass_name eq $class) {
                        # we did this above, but only checked the base class
                        my $subclass_ghost_class = $subclass_name->ghost_class;
                        # TODO: MOVE
                        if ($UR::Object::all_objects_loaded->{$subclass_ghost_class}{$pending_db_object_id}) {
                            $pending_db_object = undef;
                            redo;
                        }
                        
                        my $re_bless = $subclass_is_safe_for_re_bless{$subclass_name};
                        if (not defined $re_bless) {
                            $re_bless = $dsx->_class_is_safe_to_rebless_from_parent_class($subclass_name, $class);
                            $re_bless ||= 0;
                            $subclass_is_safe_for_re_bless{$subclass_name} = $re_bless;
                        }
                        if ($re_bless) {
                            # Performance shortcut.
                            # These need to be subclassed, but there is no added data to load.
                            # Just remove and re-add from the core data structure.
                            if (my $already_loaded = $subclass_name->is_loaded($pending_db_object->id)) {
                            
                                if ($pending_db_object == $already_loaded) {
                                    print "ALREADY LOADED SAME OBJ?\n";
                                    $DB::single = 1;
                                    print "";            
                                }
                                
                                my $loading_info = $dsx->_get_object_loading_info($pending_db_object);
                                
                                # Transfer the load info for the load we _just_ did to the subclass too.
                                $loading_info->{$subclass_name} = $loading_info->{$class};
                                $loading_info = $dsx->_reclassify_object_loading_info_for_new_class($loading_info,$subclass_name);
                                
                                # This will wipe the above data from the object and the contex...
                                $pending_db_object->unload;
                                
                                # ...now we put it back for both.
                                $dsx->_add_object_loading_info($already_loaded, $loading_info);
                                $dsx->_record_that_loading_has_occurred($loading_info);
                                
                                $pending_db_object = $already_loaded;
                            }
                            else {
                                my $loading_info = $dsx->_get_object_loading_info($pending_db_object);
                                $loading_info->{$subclass_name} = delete $loading_info->{$class};
                                
                                $loading_info = $dsx->_reclassify_object_loading_info_for_new_class($loading_info,$subclass_name);
                                
                                my $prev_class_name = $pending_db_object->class;
                                my $id = $pending_db_object->id;            
                                $pending_db_object->signal_change("unload");
                                delete $UR::Object::all_objects_loaded->{$prev_class_name}->{$id};
                                delete $UR::Object::all_objects_are_loaded->{$prev_class_name};
                                bless $pending_db_object, $subclass_name;
                                $UR::Object::all_objects_loaded->{$subclass_name}->{$id} = $pending_db_object;
                                $pending_db_object->signal_change("load");            
                                
                                $dsx->_add_object_loading_info($pending_db_object, $loading_info);
                                $dsx->_record_that_loading_has_occurred($loading_info);
                            }
                        }
                        else
                        {
                            # This object cannot just be re-classified into a subclass because the subclass joins to additional tables.
                            # We'll make a parallel iterator for each subclass we encounter.
                            
                            # Decrement all of the param_keys it is using.
                            my $loading_info = $dsx->_get_object_loading_info($pending_db_object);
                            $loading_info = $dsx->_reclassify_object_loading_info_for_new_class($loading_info,$subclass_name);
                            my $id = $pending_db_object->id;
                            $pending_db_object->unload;
                            $dsx->_record_that_loading_has_occurred($loading_info);

                            my $sub_iterator = $subordinate_iterator_for_class{$subclass_name};
                            unless ($sub_iterator) {
                                #print "parallel iteration for loading $subclass_name under $class!\n";
                                my $sub_classified_rule_template = $rule_template->sub_classify($subclass_name);
                                my $sub_classified_rule = $sub_classified_rule_template->get_rule_for_values(@values);
                                $sub_iterator 
                                    = $subordinate_iterator_for_class{$subclass_name} 
                                        = $self->_create_import_iterator_for_underlying_context($sub_classified_rule,$dsx);
                            }
                            my $last_db_object = $pending_db_object;
                            ($pending_db_object) = $sub_iterator->();
                            if (! defined $pending_db_object) {
                                # the newly subclassed object 
                                redo;
                            }
                            unless ($pending_db_object->id eq $id) {
                                Carp::cluck("object id $pending_db_object->{id} does not match expected id $id");
                                $DB::single = 1;
                                print "";
                                die;
                            }
                        }
                        
                        # the object may no longer match the rule after subclassifying...
                        unless ($rule->evaluate($pending_db_object)) {
                            #print "Object does not match rule!" . Dumper($pending_db_object,[$rule->params_list]) . "\n";
                            $pending_db_object = undef;
                            redo;
                        }
                        
                    } # end of sub-classification code
                    
                    # Signal that the object has been loaded
                    # NOTE: until this is done indexes cannot be used to look-up an object
                    #$pending_db_object->signal_change('load_external');
                    $pending_db_object->signal_change('load');                    
                
                    #$DB::single = 1;
                    if ($needs_further_boolexpr_evaluation_after_loading && ! $rule->evaluate($pending_db_object)) {
                        $pending_db_object = undef;
                        redo;
                    }
		}
                
                # When there is recursion in the query, we record data from each 
                # recursive "level" as though the query was done individually.
                if ($recursion_desc) {                    
                    # if we got a row from a query, the object must have
                    # a db_committed or db_saved_committed                                
                    my $dbc = $pending_db_object->{db_committed} || $pending_db_object->{db_saved_uncommitted};
                    die 'this should not happen' unless defined $dbc;
                    
                    my $value_by_which_this_object_is_loaded_via_recursion = $dbc->{$recurse_property_on_this_row};
                    my $value_referencing_other_object = $dbc->{$recurse_property_referencing_other_rows};
                    
                    unless ($recurse_property_value_found{$value_referencing_other_object}) {
                        # This row points to another row which will be grabbed because the query is hierarchical.
                        # Log the smaller query which would get the hierarchically linked data directly as though it happened directly.
                        $recurse_property_value_found{$value_referencing_other_object} = 1;
                        # note that the direct query need not be done again
                        my $equiv_params = $class->get_rule_for_params($recurse_property_on_this_row => $value_referencing_other_object);
                        my $equiv_param_key = $equiv_params->get_normalized_rule_equivalent->id;                
                        
                        # note that the recursive query need not be done again
                        my $equiv_params2 = $class->get_rule_for_params($recurse_property_on_this_row => $value_referencing_other_object, -recurse => $recursion_desc);
                        my $equiv_param_key2 = $equiv_params2->get_normalized_rule_equivalent->id;
                        
                        # For any of the hierarchically related data which is already loaded, 
                        # note on those objects that they are part of that query.  These may have loaded earlier in this
                        # query, or in a previous query.  Anything NOT already loaded will be hit later by the if-block below.
                        my @subset_loaded = $class->is_loaded($recurse_property_on_this_row => $value_referencing_other_object);
                        $UR::Object::all_params_loaded->{$class}{$equiv_param_key} = scalar(@subset_loaded);
                        $UR::Object::all_params_loaded->{$class}{$equiv_param_key2} = scalar(@subset_loaded);
                        for my $pending_db_object (@subset_loaded) {
                            $pending_db_object->{load}->{param_key}{$class}{$equiv_param_key}++;
                            $pending_db_object->{load}->{param_key}{$class}{$equiv_param_key2}++;
                        }
                    }
                    
                    if ($recurse_property_value_found{$value_by_which_this_object_is_loaded_via_recursion}) {
                        # This row was expected because some other row in the hierarchical query referenced it.
                        # Up the object count, and note on the object that it is a result of this query.
                        my $equiv_params = $class->get_rule_for_params($recurse_property_on_this_row => $value_by_which_this_object_is_loaded_via_recursion);
                        my $equiv_param_key = $equiv_params->get_normalized_rule_equivalent->id;
                        
                        # note that the recursive query need not be done again
                        my $equiv_params2 = $class->get_rule_for_params($recurse_property_on_this_row => $value_by_which_this_object_is_loaded_via_recursion, -recurse => $recursion_desc);
                        my $equiv_param_key2 = $equiv_params2->get_normalized_rule_equivalent->id;
                        
                        $UR::Object::all_params_loaded->{$class}{$equiv_param_key}++;
                        $UR::Object::all_params_loaded->{$class}{$equiv_param_key2}++;
                        $pending_db_object->{load}->{param_key}{$class}{$equiv_param_key}++;
                        $pending_db_object->{load}->{param_key}{$class}{$equiv_param_key2}++;                
                    }
                }
            }; # end of the for(1) block which gets the next db row (runs once unless it hits objects to skip)
            
            last unless $pending_db_object;
            push @return_objects, $pending_db_object;
            $countdown--;
        }
        
        return @return_objects;
    }; # end of iterator closure
    
    return $iterator;
}


sub _get_objects_for_class_and_sql {
    # this is a depracated back-door to get objects with raw sql
    # only use it if you know what you're doing
    my ($self, $class, $sql) = @_;
    my $meta = $class->get_class_object;        
    my $ds = $self->resolve_data_sources_for_class_meta_and_rule($meta,$class->get_rule_for_params());    
    my @ids = $ds->_resolve_ids_from_class_name_and_sql($class,$sql);
    return unless @ids;

    my $rule = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($class,id => \@ids);    
    
    return $self->get_objects_for_class_and_rule($class,$rule);
}

sub _cache_is_complete_for_class_and_normalized_rule {
    my ($self,$class,$normalized_rule) = @_;
    my ($id,$params,@objects,$cache_is_complete);
    
    $params = $normalized_rule->legacy_params_hash;
    $id = $params->{id};

    # Determine ahead of time whether we believe the object MUST be loaded if it exists.
    # If this is true, we will shortcut out of any action which loads or prepares for loading.

    # Try to resolve without loading in cases where we are sure
    # that doing so will return the complete results.
    
    if ($params->{_id_only}) {
        # _id_only means that only id parameters were passed in.
        # Either a single id or an arrayref of ids.
        # Try to pull objects from the cache in either case
        if (ref $id) {
            # arrayref id

            # we check the immediate class and all derived
            # classes for any of the ids in the set.
            @objects =
                grep { $_ }
                map { @$_{@$id} }
                map { $all_objects_loaded->{$_} }
                ($class, $class->subclasses_loaded);

            # see if we found all of the requested objects
            if (@objects == @$id) {
                # we found them all
                # return them all
                $cache_is_complete = 1;
            }
            else {
                # Ideally we'd filter out the ones we found,
                # but that gets complicated.
                # For now, we do it the slow way for partial matches
                @objects = ();
            }
        }
        else {
            # scalar id

            # Check for objects already loaded.
            no warnings;
            if (exists $all_objects_loaded->{$class}->{$id}) {
                $cache_is_complete = 1;
                @objects =
                    grep { $_ }
                    $all_objects_loaded->{$class}->{$id};
            }
            else {
                # we already checked the immediate class,
                # so just check derived classes
                @objects =
                    grep { $_ }
                    map { $all_objects_loaded->{$_}->{$id} }
                    $class->subclasses_loaded;
                if (@objects) {
                    $cache_is_complete = 1;
                }
            }
        }
    }
    elsif ($params->{_unique}) {
        # _unique means that this set of params could never
        # result in more than 1 object.  
        
        # See if the 1 is in the cache
        # If not we have to load
        
        @objects = $self->_get_objects_for_class_and_rule_from_cache($class,$normalized_rule);
        if (@objects) {
            $cache_is_complete = 1;
        }        
    }
    
    if ($cache_is_complete) {
        # if the $cache_is_comlete, the $cached list DEFINITELY represents all objects we need to return        
        # we know that loading is NOT necessary because what we've found cached must be the entire set
        return wantarray ? (1, \@objects) : ();
    }
    
    # We need to do more checking to see if loading is necessary
    # Either the parameters were non-unique, or they were unique
    # and we didn't find the object checking the cache.

    # See if we need to do a load():

    no warnings;

    my $loading_was_done_before_with_these_params =
            # complex (non-single-id) params
            exists($params->{_param_key}) 
            && (
                # exact match to previous attempt
                exists ($all_params_loaded->{$class}->{$params->{_param_key}})
                ||
                # this is a subset of a previous attempt
                ($self->_loading_was_done_before_with_a_superset_of_this_params_hashref($params))
            );
    
    my $object_is_loaded_or_non_existent =
        $loading_was_done_before_with_these_params
        || $class->all_objects_are_loaded;
    
    if ($object_is_loaded_or_non_existent) {
        # These same non-unique parameters were used to load previously,
        # or we loaded everything at some point.
        # No load necessary.
        return 1;
    }
    else {
        # Load according to params
        return;
    }
    
} # done setting $load, and possibly filling $cached/$cache_is_complete as a side-effect


sub _get_objects_for_class_and_rule_from_cache {
    # Get all objects which are loaded in the application which match
    # the specified parameters.
    my ($self, $class, $rule, $load) = @_;
    my $template = $rule->get_rule_template;
    
    #my @param_list = $rule->params_list;
    #print "CACHE-GET: $class @param_list\n";
    
    my $strategy = $rule->{_context_query_strategy};    
    unless ($strategy) {
        if ($rule->num_values == 0) {
            $strategy = $rule->{_context_query_strategy} = "all";
        }
        elsif ($rule->is_id_only) {
            $strategy = $rule->{_context_query_strategy} = "id";
        }        
        else {
            $strategy = $rule->{_context_query_strategy} = "index";
        }
    }
    
    my @results = eval {
    
        if ($strategy eq "all") {
            return $class->all_objects_loaded();
        }
        elsif ($strategy eq "id") {
            my $id = $rule->specified_value_for_id();
            
            unless (defined $id) {
                $DB::single = 1;
                $id = $rule->specified_value_for_id();
            }
            
            # Try to get the object(s) from this class directly with the ID.
            # Note that the code below is longer than it needs to be, but
            # is written to run quickly by resolving the most common cases
            # first, and gathering data only if and when it must.
    
            my @matches;
            if (ref($id) eq 'ARRAY') {
                # The $id is an arrayref.  Get all of the set.
                @matches = grep { $_ } map { @$_{@$id} } map { $all_objects_loaded->{$_} } ($class);
                
                # We're done if the number found matches the number of ID values.
                return @matches if @matches == @$id;
            }
            else {
                # The $id is a normal scalar.
                if (not defined $id) {
                    Carp::cluck("Undefined id passed as params!");
                }
                my $match = $all_objects_loaded->{$class}->{$id};
    
                # We're done if we found anything.  If not we keep checking.
                return $match if $match;
            }
    
            # Try to get the object(s) from this class's subclasses.
            # We may be adding to matches made above is we used an arrayref
            # and the results are incomplete.
    
            my @subclasses_loaded = $class->subclasses_loaded;
            return @matches unless @subclasses_loaded;
    
            if (ref($id) eq 'ARRAY') {
                # The $id is an arrayref.  Get all of the set and add it to anything found above.
                push @matches,
                    grep { $_  }
                    map { @$_{@$id} }
                    map { $all_objects_loaded->{$_} }
                    @subclasses_loaded;    
            }
            else {
                # The $id is a normal scalar, but we didn't find it above.
                # Try each subclass, exiting if we find anything.
                for (@subclasses_loaded) {
                    my $match = $all_objects_loaded->{$_}->{$id};
                    return $match if $match;
                }
            }
            
            # Since an ID was specified, and we've scanned the core hash every way possible,
            # we're done.  Return nothing if necessary.
            return @matches;
        }
        elsif ($strategy eq "index") {
            my %params = $rule->params_list;
            for my $key (keys %params) {
                delete $params{$key} if substr($key,0,1) eq '-' or substr($key,0,1) eq '_';
            }
            
            my @properties = sort keys %params;
            my @values = map { $params{$_} } @properties;
            
            unless (@properties == @values) {
                Carp::confess();
            }
            
            # find or create the index
            my $index_id = UR::Object::Index->composite_id($class,join(",",@properties));
            #my $index_id2 = $rule->index_id;
            #unless ($index_id eq $index_id2) {
            #    Carp::confess("Index ids don't match: $index_id, $index_id2\n");
            #}
            my $index = $all_objects_loaded->{'UR::Object::Index'}{$index_id};
            $index ||= UR::Object::Index->create($index_id);
            

            # add the indexed objects to the results list
            
            
            if ($UR::Debug::verify_indexes) {
                my @matches = $index->get_objects_matching(@values);        
                @matches = sort @matches;
                my @matches2 = sort grep { $rule->evaluate($_) } $class->all_objects_loaded();
                unless ("@matches" eq "@matches2") {
                    print "@matches\n";
                    print "@matches2\n";
                    $DB::single = 1;
                    #Carp::cluck("Mismatch!");
                    my @matches3 = $index->get_objects_matching(@values);
                    my @matches4 = $index->get_objects_matching(@values);                
                    return @matches2; 
                }
                return @matches;
            }
            
            return $index->get_objects_matching(@values);
        }
    };
        
    # Handle passing-through any exceptions.
    die $@ if $@;

    #if (my $recurse = $params->{-recurse}) {
    if (my $recurse = $template->recursion_desc) {        
        my ($this,$prior) = @$recurse;
        my @values = map { $_->$prior } @results;
        if (@values) {
            # We do get here, so that adjustments to intermediate foreign keys
            # in the cache will result in a new query at the correct point,
            # and not result in missing data.
            #push @results, $class->get($this => \@values, -recurse => $recurse);
            push @results, map { $class->get($this => $_, -recurse => $recurse) } @values;
        }
    }

    # Return in the standard way.
    return @results if (wantarray);
    Carp::confess("Multiple matches for $class @_!") if (@results > 1);
    return $results[0];
}

sub _loading_was_done_before_with_a_superset_of_this_params_hashref  {
    my ($self,$class,$params) = @_;

    my @property_names =
        grep {
            $_ ne "id"
                and not (substr($_,0,1) eq "_")
                and not (substr($_,0,1) eq "-")
            }
    keys %$params;

    if (@property_names < 2) {
        # we basically just tested for this above
        return;
    }
    else {
        # more than one property, see if individual checks have been done for any of these...
        for my $property_name (@property_names) {
            my $key = $class->get_rule_for_params($property_name => $params->{$property_name})->id;
            if (defined($key)
                && exists $all_params_loaded->{$class}->{$key}) {
                # DRY
                $all_params_loaded->{$class}->{$params->{_param_key}} = 1;
                my $new_key = $params->{_param_key};
                for my $obj ($class->all_objects_loaded) {
                    my $load_data = $obj->{load};
                    next unless $load_data;
                    my $param_key_data = $load_data->{param_key};
                    next unless $param_key_data;
                    my $class_data = $param_key_data->{$class};
                    next unless $class_data;
                    $class_data->{$new_key}++;
                }
                return 1;
            }
        }
    }
}

# all of these delegate to the current context...

sub has_changes {
    return shift->get_current->has_changes(@_);
}

sub get_time_ymdhms {
    my $self = shift;

    return;
    
    # TODO: go through the DBs and find one with the ability to do systime.
    # Failing that, return the local time.
    
    # Old UR::Time logic:
    
    return unless ($self->get_data_source->has_default_dbh);

    $DB::single = 1;
 
    # synchronize with the database and store the difference 
    # get database time (query is Oracle specific)
    my $date_query = q(select sysdate from dual);
    my ($db_time); # = ->dbh->selectrow_array($date_query);

    # parse database time
    my @db_now = strptime($db_time);
    if (@db_now)
    {
        # correct month and year
        ++$db_now[4];
        $db_now[5] += 1900;
        # reverse order
        @db_now = reverse((@db_now)[0 .. 5]);
    }
    else
    {
        $self->warning_message("failed to parse $db_time with strptime");
        # fall back to old method
        @db_now = split(m/[-\s:]/, $db_time);
    }
    return @db_now;
}

sub commit {
    my $self = shift;
    unless ($self->_sync_databases) {
        return;
    }
    unless ($self->_commit_databases) {
        die "Application failure during commit!";
    }
    return 1;
}

sub rollback {
    my $self = shift;
    unless ($self->_reverse_all_changes) {
        die "Application failure during reverse_all_changes?!";
    }
    unless ($self->_rollback_databases) {
        die "Application failure during rollback!";
    }
    return 1;
}

sub clear_cache {
    my $class = shift;
    my %args = @_;

    # dont unload any of the infrastructional classes, or any classes
    # the user requested to be saved
    my %local_dont_unload;
    if ($args{'dont_unload'}) {
        for my $class_name (@{$args{'dont_unload'}}) {
            $local_dont_unload{$class_name} = 1;
            for my $subclass_name ($class_name->subclasses_loaded) {
                $local_dont_unload{$subclass_name} = 1;
            }
        }
    }

    for my $class_name (UR::Object->subclasses_loaded) {

        # Once transactions are fully implemented, the command params will sit
        # beneath the regular transaction, so we won't need this.  For now,
        # we need a work-around.
        next if $class_name eq "UR::Command::Param";
        next if $class_name->isa('UR::Singleton');
        
        my $class_obj = $class_name->get_class_object;
        #if ($class_obj->data_source and $class_obj->is_transactional) {
        #    # normal
        #}
        #elsif (!$class_obj->data_source and !$class_obj->is_transactional) {
        #    # expected
        #}
        #elsif ($class_obj->data_source and !$class_obj->is_transactional) {
        #    Carp::confess("!!!!!data source on non-transactional class $class_name?");
        #}
        #elsif (!$class_obj->data_source and $class_obj->is_transactional) {
        #    # okay
        #}

        next if $class_obj->is_meta_meta;
        next unless $class_obj->is_transactional;

        next if ($local_dont_unload{$class_name} ||
                 grep { $class_name->isa($_) } @{$args{'dont_unload'}});

        next if $class_obj->is_meta;

        for my $obj ($class_name->all_objects_loaded_unsubclassed()) {
            # Check the type against %local_dont_unload again, because all_objects_loaded()
            # will return child class objects, as well as the class you asked for.  For example,
            # GSC::DNA->a_o_l() will also return GSC::ReadExp objects, and the user may have wanted
            # to save those.  We also check whether the $obj type isa one of the requested classes
            # because, for example, GSC::Sequence->a_o_l returns GSC::ReadExp types, and the user
            # may have wanted to save all GSC::DNAs
            my $obj_type = ref $obj;
            next if ($local_dont_unload{$obj_type} ||
                     grep {$obj_type->isa($_) } @{$args{'dont_unload'}});
            $obj->unload;
        }
        my @obj = grep { defined($_) } values %{ $UR::Object::all_objects_loaded->{$class_name} };
        if (@obj) {
            $class->warning_message("Skipped unload of $class_name objects during clear_cache: "
                . join(",",map { $_->id } @obj )
                . "\n"
            );
            if (my @changed = grep { $_->changed } @obj) {
                require YAML;
                $class->error_message(
                    "The following objects have changes:\n"
                    . YAML::Dump(\@changed)
                    . "The clear_cache method cannot be called with unsaved changes on objects.\n"
                    . "Use reverse_all_changes() first to really undo everything, then clear_cache(),"
                    . " or call sync_database() and clear_cache() if you want to just lighten memory but keep your changes.\n"
                    . "Clearing the cache with active changes will be supported after we're sure all code like this is gone. :)\n"                    
                );
                exit 1;
            }
        }
        delete $UR::Object::all_objects_loaded->{$class_name};
        delete $UR::Object::all_objects_are_loaded->{$class_name};
        delete $UR::Object::all_params_loaded->{$class_name};
    }
    1;
}

our $IS_SYNCING_DATABASE = 0;
sub _sync_databases {
    my $self = shift;
    my %params = @_;

    # Glue App::DB->sync_database with UR::Context->_sync_databases()
    # and avoid endless recursion.
    # FIXME Remove this when we're totally off of the old API
    # You'll also want to remove all the gotos from this function and uncomment
    # the returns
    return 1 if $IS_SYNCING_DATABASE;
    $IS_SYNCING_DATABASE = 1;
    if ($App::DB::{'sync_database'}) {
        unless (App::DB->sync_database() ) {
            $IS_SYNCING_DATABASE = 0;
            $self->error_message(App::DB->error_message());
            return;
        }
    }
    $IS_SYNCING_DATABASE = 0;  # This should be far down enough to avoid recursion, right?
    
    # Determine what has changed.
    my @changed_objects = (
        UR::Object::Ghost->all_objects_loaded,
        grep { $_->changed } UR::Object->all_objects_loaded
    );

    return 1 unless (@changed_objects);

    # Ensure validity.
    # This is primarily to catch custom validity logic in class overrides.
    my @invalid = grep { $_->invalid } @changed_objects;
    if (@invalid) {
        # Create a helpful error message for the developer.
        my $msg = "Invalid data for save!";
        $self->error_message($msg);
        my @msg;
        for my $obj (@invalid)
        {
            no warnings;
            my @problems = $obj->invalid;
            push @msg,
                $obj->display_name_full
                . " has "
                . join
                (
                    ", ",
                    (
                        map
                        {
                            $_->desc . "  Problems on "
                            . join(",", $_->property_names)
                            . " values ("
                            . join(",", map { $obj->$_ } $_->property_names)
                            . ")"
                        } @problems
                    )
                )
                . ".\n";
        }
        $self->error_message($msg . ": " . join("  ", @msg));
        goto PROBLEM_SAVING;
        #return;
    }

    # group changed objects by data source
    my %ds_objects;
    for my $obj (@changed_objects) {
        my $data_source = $self->resolve_data_source_for_object($obj);
        next unless $data_source;
        $data_source = $data_source->class;        
        $ds_objects{$data_source} ||= [];
        push @{ $ds_objects{$data_source} }, $obj;
    }

    my @ds_in_order = 
        sort {
            ($a->can_savepoint <=> $b->can_savepoint)
            || 
            ($a cmp $b)
        }
        keys %ds_objects;

    # save on each in succession
    my @done;
    my $rollback_on_non_savepoint_handle;
    for my $data_source (@ds_in_order) {
        my $obj_list = $ds_objects{$data_source};

# Testing code for sorting objects getting saved to try and validate UR with analyze traces
## Break into classes, sort by ID properties and then joing 'em all back together for testing
#my %objs_by_class;
#foreach my $obj ( @$obj_list ) {
#  my $class_name = $obj->get_class_object->class_name;
#  push @{$objs_by_class{$class_name}}, $obj;
#}
#my @sorted_objs;
#foreach my $class_name ( sort keys %objs_by_class ) {
#  my $sorter = App::Object::Class->get(class_name => $class_name)->id_property_sorter;
#  push @sorted_objs, sort $sorter @{$objs_by_class{$class_name}};
#}
#$obj_list = \@sorted_objs;

        my $result = $data_source->_sync_database(
            %params,
            changed_objects => $obj_list,
        );
        if ($result) {
            push @done, $data_source;
            next;
        }
        else {
            $self->error_message(
                "Failed to sync data source: $data_source: "
                . $data_source->error_message
            );
            for my $prev_data_source (@done) {
                $prev_data_source->_reverse_sync_database;
            }
            goto PROBLEM_SAVING;
            #return;
        }
    }
    
    return 1;

    PROBLEM_SAVING:
    if ($App::DB::{'rollback'}) {
        App::DB->rollback();
    }
    return;
}

sub _reverse_all_changes {
    my $class = shift;

    @UR::Context::Transaction::open_transaction_stack = ();
    @UR::Context::Transaction::change_log = ();
    $UR::Context::Transaction::log_all_changes = 0;
    
    
    # aggregate the objects to be deleted
    # this prevents cirucularity, since some objects 
    # can seem re-reversible (like ghosts)
    my %delete_objects;
    my @all_subclasses_loaded = sort UR::Object->subclasses_loaded;
    for my $class_name (@all_subclasses_loaded) { 
        next unless $class_name->can('get_class_object');
        
        my @objects_this_class = $class_name->all_objects_loaded_unsubclassed();
        next unless @objects_this_class;
        
        $delete_objects{$class_name} = \@objects_this_class;
    }
    
    # do the reverses
    for my $class_name (keys %delete_objects) {
        my $co = $class_name->get_class_object;
        next unless $co->is_transactional;

        my $objects_this_class = $delete_objects{$class_name};

        if ($class_name->isa("UR::Object::Ghost")) {
            # ghose placeholder for a deleted object
            for my $object (@$objects_this_class) {
                # revive ghost object
    
                my $ghost_copy = eval("no strict; no warnings; " . Data::Dumper::Dumper($object));
                if ($@) {
                    Carp::confess("Error re-constituting ghost object: $@");
                }
                my $new_object = $object->live_class->UR::Object::create(
                    %{ $ghost_copy->{db_committed} },                    
                );
                $new_object->{db_committed} = $ghost_copy->{db_committed};
                unless ($new_object) {
                    Carp::confess("Failed to re-constitute $object!");
                }
                next;
            }
        }       
        else {
            # non-ghost regular entity
            for my $object (@$objects_this_class) {
                # find property_names (that have columns)
                # todo: switch to check persist
                my %property_names =
                    map { $_->property_name => $_ }
                    grep { defined $_->column_name }
                    $co->get_all_property_objects
                ;
        
                # find columns which make up the primary key
                # convert to a hash where property => 1
                my @id_property_names = $co->all_id_property_names;
                my %id_props = map {($_, 1)} @id_property_names;
        
                
                my $saved = $object->{db_saved_uncommitted} || $object->{db_committed};
                
                if ($saved) {
                    # Existing object.  Undo all changes since last sync, 
                    # or since load occurred when there have been no syncs.
                    foreach my $property_name ( keys %property_names ) {
                        # only do this if the column is not part of the
                        # primary key
                        next if ($id_props{$property_name} ||
                                 $property_names{$property_name}->is_indirect ||
                                 $property_names{$property_name}->is_transient);
                        $object->$property_name($saved->{$property_name});
                    }
                }
                else {
                    # Object not in database, get rid of it.
                    # Because we only go back to the last sync not (not last commit),
                    # this no longer has to worry about rolling back an uncommitted database save which may have happened.
                    UR::Object::delete($object);
                }

            } # next non-ghost object
        } 
    } # next class
    return 1;
}

our $IS_COMMITTING_DATABASE = 0;
sub _commit_databases {
    my $class = shift;

    # Glue App::DB->commit() with UR::Context->_commit_databases()
    # and avoid endless recursion.
    # FIXME Remove this when we're totally off of the old API
    return 1 if $IS_COMMITTING_DATABASE;
    $IS_COMMITTING_DATABASE = 1;
    if ($App::DB::{'commit'}) {
        unless (App::DB->commit() ) {
	    $IS_COMMITTING_DATABASE = 0;
            $class->error_message(App::DB->error_message());
            return;
        }
    }
    $IS_COMMITTING_DATABASE = 0;

    unless ($class->_for_each_data_source("commit")) {
        if ($class->error_message eq "PARTIAL commit") {
            die "FRAGMENTED DISTRIBUTED TRANSACTION\n"
                . Data::Dumper::Dumper($UR::Object::all_objects_loaded)
        }
        else {
            die "FAILED TO COMMIT!: " . $class->error_message;
        }
    }
    return 1;
}


our $IS_ROLLINGBACK_DATABASE = 0;
sub _rollback_databases {
    my $class = shift;

    # Glue App::DB->rollback() with UR::Context->_rollback_databases()
    # and avoid endless recursion.
    # FIXME Remove this when we're totally off of the old API
    return 1 if $IS_ROLLINGBACK_DATABASE;
    $IS_ROLLINGBACK_DATABASE = 1;
    if ($App::DB::{'rollback'}) {
        unless (App::DB->rollback()) {
            $IS_ROLLINGBACK_DATABASE = 0;
            $class->error_message(App::DB->error_message());
            return;
        }
    }
    $IS_ROLLINGBACK_DATABASE = 0;

    $class->_for_each_data_source("rollback")
        or die "FAILED TO ROLLBACK!: " . $class->error_message;
    return 1;
}

sub _disconnect_databases {
    my $class = shift;
    $class->_for_each_data_source("disconnect");
    return 1;
}    

sub _all_active_dbhs {
    my $class = shift;
    my @ds = UR::DataSource->all_objects_loaded();
    my @dbh;
    for my $ds (@ds) {
        next unless $ds->has_default_dbh;
        my $dbh = $ds->get_default_dbh;
        push  @dbh, $dbh;
    }
    return @dbh;
}

sub _for_each_data_source {
    my($class,$method) = @_;

    my @ds = UR::DataSource->all_objects_loaded();
    foreach my $ds ( @ds ) {
       unless ($ds->$method) {
           $class->error_message("$method failed on DataSource ",$ds->get_name);
           return; 
       }
    }
    return 1;
}

sub _for_each_dbh
{
    my $class = shift;
    my $method = shift;
    my @dbh = $class->_all_active_dbhs;
    my @ok;
    for my $dbh (@dbh) {
        if ($dbh->$method) {
            push @ok, $dbh;
        }
        else {
            $class->error_message(
                $dbh->errstr
                . (@ok ? "\nPARTIAL $method" : "")
            );
            return;
        }
    }
    return 1;
}

sub _get_committed_property_value {
    my $class = shift;
    my $object = shift;
    my $property_name = shift;

    if ($object->{'db_committed'}) {
        return $object->{'db_committed'}->{$property_name};
    } elsif ($object->{'db_saved_uncommitted'}) {
        return $object->{'db_saved_uncommitted'}->{$property_name};
    } else {
        return;
    }
}

sub _dump_change_snapshot {
    my $class = shift;
    my %params = @_;

    my @c = grep { $_->changed } UR::Object->all_objects_loaded;

    my $fh;
    if (my $filename = $params{filename})
    {
        $fh = IO::File->new(">$filename");
        unless ($fh)
        {
            $class->error_message("Failed to open file $filename: $!");
            return;
        }
    }
    else
    {
        $fh = "STDOUT";
    }
    require YAML;
    $fh->print(YAML::Dump(\@c));
    $fh->close;
}


our $CORE_DUMP_VERSION = 1;
# Use Data::Dumper to save a representation of the object cache to a file.  Args are:
# filename => the name of the file to save to
# dumpall => boolean flagging whether to dump _everything_, or just the things
#            that would actually be loaded later in core_restore()

sub _core_dump {
    my $class = shift;
    my %args = @_;

    my $filename = $args{'filename'} || "/tmp/core." . UR::Context::Process->prog_name . ".$ENV{HOST}.$$";
    my $dumpall = $args{'dumpall'};

    my $fh = IO::File->new(">$filename");
    if (!$fh) {
      $class->error_message("Can't open dump file $filename for writing: $!");
      return undef;
    }

    my $dumper;
    if ($dumpall) {  # Go ahead and dump everything
        $dumper = Data::Dumper->new([$CORE_DUMP_VERSION,
                                     $UR::Object::all_objects_loaded,
                                     $UR::Object::all_objects_are_loaded,
                                     $UR::Object::all_params_loaded,
                                     $UR::Object::all_change_subscriptions],
                                    ['dump_version','all_objects_loaded','all_objects_are_loaded',
                                     'all_params_loaded','all_change_subscriptions']);
    } else {
        my %DONT_UNLOAD =
            map {
                my $co = $_->get_class_object;
                if ($co and not $co->is_transactional) {
                    ($_ => 1)
                }
                else {
                    ()
                }
            }
            UR::Object->all_objects_loaded;

        my %aol = map { ($_ => $UR::Object::all_objects_loaded->{$_}) }
                     grep { ! $DONT_UNLOAD{$_} } keys %$UR::Object::all_objects_loaded;
        my %aoal = map { ($_ => $UR::Object::all_objects_are_loaded->{$_}) }
                      grep { ! $DONT_UNLOAD{$_} } keys %$UR::Object::all_objects_are_loaded;
        my %apl = map { ($_ => $UR::Object::all_params_loaded->{$_}) }
                      grep { ! $DONT_UNLOAD{$_} } keys %$UR::Object::all_params_loaded;
        # don't dump $UR::Object::all_change_subscriptions
        $dumper = Data::Dumper->new([$CORE_DUMP_VERSION,\%aol, \%aoal, \%apl],
                                    ['dump_version','all_objects_loaded','all_objects_are_loaded',
                                     'all_params_loaded']);

    }

    $dumper->Purity(1);   # For dumping self-referential data structures
    $dumper->Sortkeys(1); # Makes quick and dirty file comparisons with sum/diff work correctly-ish

    $fh->print($dumper->Dump() . "\n");

    $fh->close;

    return $filename;
}


# Read a file previously generated with core_dump() and repopulate the object cache.  Args are:
# filename => name of the coredump file
# force => boolean flag whether to go ahead and attempt to load the file even if it thinks
#          there is a formatting problem
sub _core_restore {
    my $class = shift;
    my %args = @_;
    my $filename = $args{'filename'};
    my $forcerestore = $args{'force'};

    my $fh = IO::File->new("$filename");
    if (!$fh) {
        $class->error_message("Can't open dump file $filename for restoring: $!");
        return undef;
    }

    my $code;
    while (<$fh>) { $code .= $_ }

    my($dump_version,$all_objects_loaded,$all_objects_are_loaded,$all_params_loaded,$all_change_subscriptions);
    eval $code;

    if ($@)
    {
        $class->error_message("Failed to restore core file state: $@");
        return undef;
    }
    if ($dump_version != $CORE_DUMP_VERSION) {
      $class->error_message("core file's version $dump_version differs from expected $CORE_DUMP_VERSION");
      return 0 unless $forcerestore;
    }

    my %DONT_UNLOAD =
        map {
            my $co = $_->get_class_object;
            if ($co and not $co->is_transactional) {
                ($_ => 1)
            }
            else {
                ()
            }
        }
        UR::Object->all_objects_loaded;

    # Go through the loaded all_objects_loaded, prune out the things that
    # are in %DONT_UNLOAD
    my %loaded_classes;
    foreach ( keys %$all_objects_loaded ) {
        next if ($DONT_UNLOAD{$_});
        $UR::Object::all_objects_loaded->{$_} = $all_objects_loaded->{$_};
        $loaded_classes{$_} = 1;

    }
    foreach ( keys %$all_objects_are_loaded ) {
        next if ($DONT_UNLOAD{$_});
        $UR::Object::all_objects_are_loaded->{$_} = $all_objects_are_loaded->{$_};
        $loaded_classes{$_} = 1;
    }
    foreach ( keys %$all_params_loaded ) {
        next if ($DONT_UNLOAD{$_});
        $UR::Object::all_params_loaded->{$_} = $all_params_loaded->{$_};
        $loaded_classes{$_} = 1;
    }
    # $UR::Object::all_change_subscriptions is basically a bunch of coderef
    # callbacks that can't reliably be dumped anyway, so we skip it

    # Now, get the classes to instantiate themselves
    foreach ( keys %loaded_classes ) {
        $_->class() unless m/::Ghost$/;
    }

    return 1;
}

1;
