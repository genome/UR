package UR::Context;

use strict;
use warnings;
use Date::Parse;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Context',    
    is_abstract => 1,
    has => [
        parent  => { is => 'UR::Context', id_by => 'parent_id', is_optional => 1 }
    ],
    doc => <<EOS
The environment in which oo-activity occurs in UR.  Subclasses exist for in-memory transactions,
and also the process itself, the environment in which activity occurs at an organization (the root).
This is responsible for mapping object requests to database requests, managing caching, transaction
consistency, locking, etc.
EOS
);

# These are all owned by the "process" context.
our $all_objects_loaded ||= {};               # Master index of all tracked objects by class and then id.
our $all_change_subscriptions ||= {};         # Index of other properties by class, property_name, and then value.
our $all_objects_are_loaded ||= {};           # Track when a class informs us that all objects which exist are loaded.
our $all_params_loaded ||= {};                # Track parameters used to load by class then _param_key

# for bootstrapping
$UR::Context::current = __PACKAGE__;

# called by UR.pm during bootstraping
my $initialized = 0;
sub _initialize_for_current_process {
    my $class = shift;
    if ($initialized) {
        die "Attempt to re-initialize the current process?";
    }

    my $root_id = $ENV{UR_CONTEXT_ROOT} ||= 'UR::Context::DefaultRoot';
    $UR::Context::root = UR::Context::Root->get($root_id);
    unless ($UR::Context::root) {
        die "Failed to find root context object '$root_id':!?  Odd value in environment variable UR_CONTEXT_ROOT?";
    }

    if (my $base_id = $ENV{UR_CONTEXT_BASE}) {
        $UR::Context::base = UR::Context::Process->get($base_id);
        unless ($UR::Context::base) {
            die "Failed to find base context object '$base_id':!?  Odd value in environment variable UR_CONTEXT_BASE?";
        }
    } 
    else {
        $UR::Context::base = $UR::Context::root;
    }

    $UR::Context::process = UR::Context::Process->_create_for_current_process(parent_id => $UR::Context::base);

    # This changes when we initiate in-memory transactions on-top of the basic, heavier weight one for the process.
    $UR::Context::current = $UR::Context::process;
}

sub get_default_data_source {
    # TODO: a context should be able to specify a specific place to go for general data.
    # This is used only to get things like the system time, etc.
    my @ds = UR::DataSource->is_loaded();
    return $ds[0];
}

# the rot context is the root snapshot of reality the application is using
# it only varies when we flip to development/testing etc.

sub get_root {
    return $UR::Context::root;
}

# the base context is whatever context is immediately outside the process: typically the root context

sub get_base {
    return $UR::Context::base;
}

# the process context is the perspective on the data from the current process/thread
# this is primarily for buffering, when the process is the current process

sub get_process {
    return $UR::Context::process;
}

# the current context is either the process context, or the current transaction on-top of it

sub get_current {
    return $UR::Context::current;
}

# how did this get here?

sub send_email {
    my $self = shift;
    my $base = $self->get_base;
    $base->_send_email(@_);
}

# this is used to determine which data source/sources to use for loading objects matching a given rule

our $data_source_mapping = {};

sub set_data_sources {
    my $self = shift;
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
        #$class_name->get_class_object->data_source($data_source_detail);
    } 
}

sub class_names_for_data_source {
    my($self,$data_source_detail) = @_;

    my $ds_id = $data_source_detail->id;

    my @class_names;
    foreach my $class_name ( keys %$data_source_mapping ) {
        foreach my $override ( @{$data_source_mapping->{$class_name}} ) {
            if ($override->{'data_source'}->id eq $ds_id) {
                push @class_names, $class_name;
            }
        }
    }
    return @class_names;
}

sub resolve_data_sources_for_class_meta_and_rule {
    my $self = shift;
    my $class_meta = shift;
    my $boolexpr = shift;  ## ignored in the default case    

    my $class_name = $class_meta->class_name;

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

    my $data_source;

    if (my $mapping = $data_source_mapping->{$class_name}) {
        my $class_name = $boolexpr->subject_class_name;
        for my $possible_ds_data (@$mapping) {
            #my $ds_boolexpr_id = $possible_ds_data->{boolexpr_id};
            #my $ds_boolexpr = UR::BoolExpr->get($ds_boolexpr_id);
            #if ($boolexpr->might_overlap($ds_boolexpr)) {
                $data_source = $possible_ds_data->{data_source};
            #}
        }

    # For data dictionary items
    } elsif ($class_name =~ m/^UR::DataSource::RDBMS::(.*)/) {
        if (!defined $boolexpr) {
            $DB::single=1;
        }

        my $params = $boolexpr->legacy_params_hash;
        if ($params->{'namespace'}) {
            $data_source = $params->{'namespace'} . '::DataSource::Meta';

        } elsif ($params->{'data_source'} &&
                 ! ref($params->{'data_source'}) &&
                 $params->{'data_source'}->can('get_namespace')) {

            my $namespace = $params->{'data_source'}->get_namespace;
            $data_source = $namespace . '::DataSource::Meta';

        } elsif ($params->{'data_source'} &&
                 ref($params->{'data_source'}) eq 'ARRAY') {
            my %namespaces = map { $_->get_namespace => 1 } @{$params->{'data_source'}};
            unless (scalar(keys %namespaces) == 1) {
                Carp::confess("get() across multiple namespaces is not supported");
            }
            my $namespace = $params->{'data_source'}->[0]->get_namespace;
            $data_source = $namespace . '::DataSource::Meta';
        } else {
            Carp::confess("Required parameter (namespace or data_source) missing");
            #$data_source = 'UR::DataSource::Meta';
        }

    } else {
        $data_source = $class_meta->data_source;
    }

    if ($data_source) {
        $data_source = $data_source->resolve_data_sources_for_rule($boolexpr);
    }
    return $data_source;
}


# this is used to determine which data source an object should be saved-to

sub resolve_data_source_for_object {
    my $self = shift;
    my $object = shift;
    my $class_meta = $object->get_class_object;
    my $class_name = $class_meta->class_name;
    
    # FIXME this pattern match is going to get called a lot.
    # Make up something that's faster to do the job
    if ($class_meta->class_name =~ m/^UR::DataSource::RDBMS::/) {
        my $data_source = $object->data_source;
        my($namespace) = ($data_source =~ m/(^\w+?)::DataSource/);
        return $namespace . '::DataSource::Meta';
    } elsif ($data_source_mapping->{$class_name}) {
        # FIXME This assummes there will ever only be one datasource override
        # per class name.  It doesn't check the associated boolexpr
        return $data_source_mapping->{$class_name}->[0]->{'data_source'};
    }
        
    # Default behavior
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
        return @c if wantarray;           # array context
        return unless defined wantarray;  # null context
        Carp::confess("multiple objects found for a call in scalar context!  Using " . __PACKAGE__) if @c > 1;
        return $c[0];                     # scalar context
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

# A wrapper around the method of the same name in UR::DataSource::* to iterate over the
# possible data sources involved in a query.  The easy case (a query against a single data source)
# will return the $primary_template data structure.  If the query involves more than one data source,
# then this method also returns a list containing triples (@addl_loading_info) where each member is:
# 1) The secondary data source name
# 2) a listref of delegated properties joining the primary class to the secondary class
# 3) a rule template applicable against the secondary data source
sub _get_template_data_for_loading {
    my($self,$primary_data_source,$rule_template) = @_;

    my $primary_template = $primary_data_source->_get_template_data_for_loading($rule_template);

    unless ($primary_template->{'joins_across_data_sources'}) {
        # Common, easy case
        return $primary_template;
    }

    my @addl_loading_info;
    foreach my $secondary_data_source ( keys %{$primary_template->{'joins_across_data_sources'}} ) {
        my $this_ds_delegations = $primary_template->{'joins_across_data_sources'}->{$secondary_data_source};

        my @secondary_params;
        my $secondary_class;
        my %seen_properties;
        foreach my $delegated_property ( @$this_ds_delegations ) {
            my $delegated_property_name = $delegated_property->property_name;
            next if ($seen_properties{$delegated_property_name});

            my $operator = $rule_template->operator_for_property_name($delegated_property_name);
            $operator ||= '=';  # FIXME - shouldn't the template return this for us?
            push @secondary_params, $delegated_property->to . ' ' . $operator;

            unless ($secondary_class) {
                my $relation_property = UR::Object::Property->get(class_name => $delegated_property->class_name,
                                                                  property_name => $delegated_property->via);
     
                $secondary_class ||= $relation_property->data_type;
            }

            # we can also add in any properties in the property's joins that also appear in the rule
            if (@{$delegated_property->{'_get_joins'}} > 1) {
                # What does it mean if there's more than one thing in here?
                die sprintf("Property %s of class %s has more than one item in _get_joins.  I don't know what to do",
                            $delegated_property->property_name, $delegated_property->class_name);
            }
                    
            my $reference = UR::Object::Reference->get(class_name => $delegated_property->class_name,
                                                       delegation_name => $delegated_property->via);
            my @ref_properties = $reference->get_property_links();
            foreach my $ref_property ( @ref_properties ) {
                next if ($seen_properties{$ref_property->property_name});
                my $ref_property_name = $ref_property->property_name;
                next unless ($rule_template->specifies_value_for_property_name($ref_property_name));

                my $ref_operator = $rule_template->operator_for_property_name($ref_property_name);
                $ref_operator ||= '=';

                push @secondary_params, $ref_property->r_property_name . ' ' . $ref_operator;
            }

        }
        my $secondary_rule_template = UR::BoolExpr::Template->resolve_for_class_and_params($secondary_class, @secondary_params);

        push @addl_loading_info,
                 $secondary_data_source,
                 $this_ds_delegations,
                 $secondary_rule_template;
    }

    return ($primary_template, @addl_loading_info);
}


# Used by _create_secondary_loading_comparators to convert a rule against the primary data source
# to a rule that can be used against a secondary data source
sub _create_secondary_rule_from_primary {
    my($self,$primary_rule, $delegated_properties, $secondary_rule_template) = @_;

#$DB::single=1;
    my @secondary_values;
    my %seen_properties;  # FIXME - we've already been over this list in _get_template_data_for_loading()...
    # FIXME - is there ever a case where @$delegated_properties will be more than one item?
    foreach my $property ( @$delegated_properties ) {
        my $value = $primary_rule->specified_value_for_property_name($property->property_name);

        my $secondary_property_name = $property->to;
        my $pos = $secondary_rule_template->value_position_for_property_name($secondary_property_name);
        $secondary_values[$pos] = $value;
        $seen_properties{$property->property_name}++;

        my $reference = UR::Object::Reference->get(class_name => $property->class_name,
                                                   delegation_name => $property->via);
        next unless $reference;
        my @ref_properties = $reference->get_property_links();
        foreach my $ref_property ( @ref_properties ) {
            my $ref_property_name = $ref_property->property_name;
            next if ($seen_properties{$ref_property_name}++);
            $value = $primary_rule->specified_value_for_property_name($ref_property_name);
            next unless $value;

            $pos = $secondary_rule_template->value_position_for_property_name($ref_property->r_property_name);
            $secondary_values[$pos] = $value;
        }
    }

    my $secondary_rule = $secondary_rule_template->get_rule_for_values(@secondary_values);

    return $secondary_rule;
}


# Since we'll be appending more "columns" of data to the listrefs returned by
# the primary datasource's query, we need to apply fixups to the column positions
# to all the secondary loading templates
# The column_position and object_num offsets needed for the next call of this method
# are returned
sub _fixup_secondary_loading_template_column_positions {
    my($self,$primary_loading_templates, $secondary_loading_templates, $column_position_offset, $object_num_offset) = @_;

    if (! defined($column_position_offset) or ! defined($object_num_offset)) {
        $column_position_offset = 0;
        foreach my $tmpl ( @{$primary_loading_templates} ) {
            $column_position_offset += scalar(@{$tmpl->{'column_positions'}});
        }
        $object_num_offset = scalar(@{$primary_loading_templates});
    }

    my $this_template_column_count;
    foreach my $tmpl ( @$secondary_loading_templates ) {
        foreach ( @{$tmpl->{'column_positions'}} ) {
            $_ += $column_position_offset;
        }
        foreach ( @{$tmpl->{'id_column_positions'}} ) {
            $_ += $column_position_offset;
        }
        $tmpl->{'object_num'} += $object_num_offset;

        $this_template_column_count += scalar(@{$tmpl->{'column_positions'}});
    }


    return ($column_position_offset + $this_template_column_count,
            $object_num_offset + scalar(@$secondary_loading_templates) );
}


# For queries that have to hit multiple data sources, this method creates two lists of
# closures.  The first is a list of object fabricators, where the loading templates
# have been given fixups to the column positions (see _fixup_secondary_loading_template_column_positions())
# The second is a list of closures for each data source (the @addl_loading_info stuff
# from _get_template_data_for_loading) that's able to compare the row loaded from the
# primary data source and see if it joins to a row from this secondary datasource's database
sub _create_secondary_loading_closures {
    my($self, $primary_template, $rule, @addl_loading_info) = @_;

    my $loading_templates = $primary_template->{'loading_templates'};

    # Make a mapping of property name to column positions returned by the primary query
    my %primary_query_column_positions;
    foreach my $tmpl ( @$loading_templates ) {
        my $property_name_count = scalar(@{$tmpl->{'property_names'}});
        for (my $i = 0; $i < $property_name_count; $i++) {
            my $property_name = $tmpl->{'property_names'}->[$i];
            my $pos = $tmpl->{'column_positions'}->[$i];
            $primary_query_column_positions{$property_name} = $pos;
        }
    }

    my @secondary_object_importers;
    my @addl_join_comparators;

    # used to shift the apparent column position of the secondary loading template info
    my ($column_position_offset,$object_num_offset);

    while (@addl_loading_info) {
        my $secondary_data_source = shift @addl_loading_info;
        my $this_ds_delegations = shift @addl_loading_info;
        my $secondary_rule_template = shift @addl_loading_info;

        my $secondary_rule = $self->_create_secondary_rule_from_primary (
                                              $rule,
                                              $this_ds_delegations,
                                              $secondary_rule_template,
                                       );
        $secondary_data_source = $secondary_data_source->resolve_data_sources_for_rule($secondary_rule);
        my $secondary_template = $self->_get_template_data_for_loading($secondary_data_source,$secondary_rule_template);

        # sets of triples where the first in the triple is the column index in the
        # $secondary_db_row (in the join_comparator closure below), the second is the
        # index in the $next_db_row.  And the last is a flag indicating if we should 
        # perform a numeric comparison.  This way we can preserve the order the comparisons
        # should be done in
        my @join_comparison_info;
        foreach my $property ( @$this_ds_delegations ) {
            # first, map column names in the joined class to column names in the primary class
            my %foreign_property_name_map;
            my @this_property_joins = $property->_get_joins();
            foreach my $join ( @this_property_joins ) {
                my @source_names = @{$join->{'source_property_names'}};
                my @foreign_names = @{$join->{'foreign_property_names'}};
                @foreign_property_name_map{@foreign_names} = @source_names;
            }

            # Now, find out which numbered column in the result query maps to those names
            my $loading_templates = $secondary_template->{'loading_templates'};
            foreach my $tmpl ( @$loading_templates ) {
                my $property_name_count = scalar(@{$tmpl->{'property_names'}});
                for (my $i = 0; $i < $property_name_count; $i++) {
                    my $property_name = $tmpl->{'property_names'}->[$i];
                    if ($foreign_property_name_map{$property_name}) {
                        # This is the one we're interested in...  Where does it come from in the primary query?
                        my $column_position = $tmpl->{'column_positions'}->[$i];

                        # What are the types involved?
                        my $primary_property_meta = UR::Object::Property->get(class_name => $primary_template->{'class_name'},
                                                                              property_name => $foreign_property_name_map{$property_name});
                        my $secondary_property_meta = UR::Object::Property->get(class_name => $secondary_template->{'class_name'},
                                                                                property_name => $property_name);

                        my $comparison_type;
                        if ($primary_property_meta->is_numeric && $secondary_property_meta->is_numeric) {
                            $comparison_type = 1;
                        } 
                        push @join_comparison_info, $column_position,
                                                    $primary_query_column_positions{$foreign_property_name_map{$property_name}},
                                                    $comparison_type;
 

                    }
                }
            }
        }

        my $secondary_db_iterator = $secondary_data_source->create_iterator_closure_for_rule($secondary_rule);

        my $secondary_db_row;
        # For this closure, pass in the row we just loaded from the primary DB query.
        # This one will return the data from this secondary DB's row if the passed-in
        # row successfully joins to this secondary db iterator.  It returns an empty list
        # if there were no matches, and returns false if there is no more data from the query
        my $join_comparator = sub {
            my $next_db_row = shift;  # From the primary DB
            READ_DB_ROW:
            while(1) {
                return unless ($secondary_db_iterator);
                unless ($secondary_db_row) {
                    ($secondary_db_row) = $secondary_db_iterator->();
                    unless($secondary_db_row) {
                        # No more data to load 
                        $secondary_db_iterator = undef; 
                        return;
                    }
                }

                for (my $i = 0; $i < @join_comparison_info; $i += 3) {
                    my $secondary_column = $join_comparison_info[$i]; 
                    my $primary_column = $join_comparison_info[$i+1];
                    my $comparison;
                    # Numeric or string comparison?
                    if ($join_comparison_info[$i+2]) {
                        $comparison = $secondary_db_row->[$secondary_column] <=> $next_db_row->[$primary_column];
                    } else {
                        $comparison = $secondary_db_row->[$secondary_column] cmp $next_db_row->[$primary_column];
                    }

                    if ($comparison < 0) {
                        # less than, get the next row from the secondary DB
                        $secondary_db_row = undef;
                        redo READ_DB_ROW;
                    } elsif ($comparison == 0) {
                        # This one was the same, keep looking at the others
                    } else {
                        # greater-than, there's no match for this primary DB row
                        return 0;
                    }
                }
                # All the joined columns compared equal, return the data
                return $secondary_db_row;
            }
        };
        push @addl_join_comparators, $join_comparator;
 

        # And for the object importer/fabricator, here's where we need to shift the column order numbers
        # over, because these closures will be called after all the db iterators' rows are concatenated
        # together.  We also need to make a copy of the loading_templates list so as to not mess up the
        # class' notion of where the columns are
        # FIXME - it seems wasteful that we need to re-created this each time.  Look into some way of using 
        # the original copy that lives in $primary_template->{'loading_templates'}?  Somewhere else?
        my @secondary_loading_templates;
        foreach my $tmpl ( @{$secondary_template->{'loading_templates'}} ) {
            my %copy;
            foreach my $key ( keys %$tmpl ) {
                my $value_to_copy = $tmpl->{$key};
                if (ref($value_to_copy) eq 'ARRAY') {
                    $copy{$key} = [ @$value_to_copy ];
                } elsif (ref($value_to_copy) eq 'HASH') {
                    $copy{$key} = { %$value_to_copy };
                } else {
                    $copy{$key} = $value_to_copy;
                }
            }
            push @secondary_loading_templates, \%copy;
        }
            
        ($column_position_offset,$object_num_offset) =
                $self->_fixup_secondary_loading_template_column_positions($primary_template->{'loading_templates'},
                                                                          \@secondary_loading_templates,
                                                                          $column_position_offset,$object_num_offset);
 
        #my($secondary_rule_template,@secondary_values) = $secondary_rule->get_template_and_values();
        my @secondary_values = $secondary_rule->get_values();
        foreach my $secondary_loading_template ( @secondary_loading_templates ) {
            my $secondary_object_importer = $self->_create_object_fabricator_for_loading_template(
                                                       $secondary_loading_template,
                                                       $secondary_template,
                                                       $secondary_rule,
                                                       $secondary_rule_template,
                                                       \@secondary_values,
                                                       $secondary_data_source
                                                );
            push @secondary_object_importers, $secondary_object_importer;
        }
                                                       

   }

    return (\@secondary_object_importers, \@addl_join_comparators);
}


sub _create_import_iterator_for_underlying_context {
    my ($self, $rule, $dsx) = @_; 

    my ($rule_template, @values) = $rule->get_rule_template_and_values();
    my($template_data,@addl_loading_info) = $self->_get_template_data_for_loading($dsx,$rule_template);
    my $class_name = $template_data->{class_name};

    if (my $sub_typing_property) {
        # When the rule has a property specified which indicates a specific sub-type, catch this and re-call
        # this method recursively with the specific subclass name.
        
        my $rule_template_specifies_value_for_subtype   = $template_data->{rule_template_specifies_value_for_subtype};
        my $class_table_name                            = $template_data->{class_table_name};
        my @type_names_under_class_with_no_table        = @{ $template_data->{type_names_under_class_with_no_table} };
   
        warn "Implement me carefully";
        
        if ($rule_template_specifies_value_for_subtype) {
            #$DB::single = 1;
            my $sub_classification_meta_class_name          = $template_data->{sub_classification_meta_class_name};
            my $value = $rule->specified_value_for_property_name($sub_typing_property);
            my $type_obj = $sub_classification_meta_class_name->get($value);
            if ($type_obj) {
                my $subclass_name = $type_obj->subclass_name($class_name);
                if ($subclass_name and $subclass_name ne $class_name) {
                    $rule = $subclass_name->get_rule_for_params($rule->params_list, $sub_typing_property => $value);
                    return $self->_create_import_iterator_for_underlying_context($rule,$dsx);
                }
            }
            else {
                die "No $value for $class_name?\n";
            }
        }
        elsif (not $class_table_name) {
            #$DB::single = 1;
            # we're in a sub-class, and don't have the type specified
            # check to make sure we have a table, and if not add to the filter
            my $rule = $class_name->get_rule_for_params(
                $rule_template->get_rule_for_values(@values)->params_list, 
                $sub_typing_property => (@type_names_under_class_with_no_table > 1 ? \@type_names_under_class_with_no_table : $type_names_under_class_with_no_table[0]),
            );
            return $self->_create_import_iterator_for_underlying_context($rule,$dsx)
        }
        else {
            # continue normally
            # the logic below will handle sub-classifying each returned entity
        }
    }
    
    
    my $loading_templates = $template_data->{loading_templates};
    my $sub_typing_property                         = $template_data->{sub_typing_property};
    my $next_db_row;
    my $rows = 0;       # number of rows the query returned
    
    my $recursion_desc                              = $template_data->{recursion_desc};
    my $rule_template_without_recursion_desc;
    my $rule_without_recursion_desc;
    if ($recursion_desc) {
        $rule_template_without_recursion_desc        = $template_data->{rule_template_without_recursion_desc};
        $rule_without_recursion_desc                 = $rule_template_without_recursion_desc->get_rule_for_values(@values);    
    }
    
    my $needs_further_boolexpr_evaluation_after_loading = $template_data->{'needs_further_boolexpr_evaluation_after_loading'};
    
    # make an iterator for the primary data source
    my $db_iterator = $dsx->create_iterator_closure_for_rule($rule);    

    my %subordinate_iterator_for_class;
    
    # instead of making just one import iterator, we make one per loading template
    # we then have our primary iterator use these to fabricate objects for each db row
    my @importers;
    for my $loading_template (@$loading_templates) {
        my $object_fabricator = $self->_create_object_fabricator_for_loading_template($loading_template, 
                                                                                      $template_data,
                                                                                      $rule,
                                                                                      $rule_template,
                                                                                      \@values,
                                                                                      $dsx
                                                                                    );
        unshift @importers, $object_fabricator;
    }

    # For joins across data sources, we need to create importers/fabricators for those
    # classes, as well as callbacks used to perform the equivalent of an SQL join in
    # UR-space
    my @addl_join_comparators;
    if (@addl_loading_info) {
        my($addl_object_fabricators, $addl_join_comparators) =
                $self->_create_secondary_loading_closures( $template_data,
                                                           $rule,
                                                           @addl_loading_info
                                                      );

        unshift @importers, @$addl_object_fabricators;
        push @addl_join_comparators, @$addl_join_comparators;
    }

    # Make the iterator we'll return.
    my $iterator = sub {
        my $object;
        
        LOAD_AN_OBJECT:
        until ($object) { # note that we return directly when the db is out of data
            
            my ($next_db_row);
            ($next_db_row) = $db_iterator->() if ($db_iterator);

            unless ($next_db_row) {
                if ($rows == 0) {
                    # if we got no data at all from the sql then we give a status
                    # message about it and we update all_params_loaded to indicate
                    # that this set of parameters yielded 0 objects
                    
                    my $rule_template_is_id_only = $template_data->{rule_template_is_id_only};
                    if ($rule_template_is_id_only) {
                        my $id = $rule->specified_value_for_id;
                        $UR::Object::all_objects_loaded->{$class_name}->{$id} = undef;
                    }
                    else {
                        my $rule_id = $rule->id;
                        $UR::Object::all_params_loaded->{$class_name}->{$rule_id} = 0;
                    }
                }
                
                if ( $template_data->{rule_matches_all} ) {
                    # No parameters.  We loaded the whole class.
                    # Doing a load w/o a specific ID w/o custom SQL loads the whole class.
                    # Set a flag so that certain optimizations can be made, such as 
                    # short-circuiting future loads of this class.        
                    $class_name->all_objects_are_loaded(1);        
                }
                
                if ($recursion_desc) {
                    my @results = $class_name->is_loaded($rule_without_recursion_desc);
                    $UR::Object::all_params_loaded->{$class_name}{$rule_without_recursion_desc->id} = scalar(@results);
                    for my $object (@results) {
                        $object->{load}{param_key}{$class_name}{$rule_without_recursion_desc->id}++;
                    }
                }
                return;
            }
            
            # we count rows processed mainly for more concise sanity checking
            $rows++;

            # For multi-datasource queries, does this row successfully join with all the other datasources?
            #
            # Normally, the policy is for the data source query to return (possibly) more than what you
            # asked for, and then we'd cache everything that may have been loaded.  In this case, we're
            # making the choice not to.  Reason being that a join across databases is likely to involve
            # a lot of objects, and we don't want to be stuffing our object cache with a lot of things
            # we're not interested in.  FIXME - in order for this to be true, then we could never query
            # these secondary data sources against, say, a calculated property because we're never turning
            # them into objects.  FIXME - fix this by setting the $needs_further_boolexpr_evaluation_after_loading
            # flag maybe?
            my @secondary_data;
            foreach my $callback (@addl_join_comparators) {
                # FIXME - (no, not another one...) There's no mechanism for duplicating SQL join's
                # behavior where if a row from a table joins to 2 rows in the secondary table, the 
                # first table's data will be in the result set twice.
                my $secondary_db_row = $callback->($next_db_row);
                unless (defined $secondary_db_row) {
                    # That data source has no more data, so there can be no more joins even if the
                    # primary data source has more data left to read
                    return;
                }
                unless ($secondary_db_row) {  
                    # It returned 0
                    # didn't join (but there is still more data we can read later)... throw this row out.
                    $object = undef;
                    redo LOAD_AN_OBJECT;
                }
                # $next_db_row is a read-only value from DBI, so we need to track our additional 
                # data seperately and smash them together before the object importer is called
                push(@secondary_data, @$secondary_db_row);
            }
            
            # get one or more objects from this row of results
            my $re_iterate = 0;
            my @imported;
            for my $callback (@importers) {
                # The usual case is that the query is just against one data source, and so the importer
                # callback is just given the row returned from the DB query.  For multiple data sources,
                # we need to smash together the primary and all the secondary lists
                my $imported_object;
                if (@secondary_data) {
                    $imported_object = $callback->([@$next_db_row, @secondary_data]);
                } else { 
                    $imported_object = $callback->($next_db_row);
                }
                    
                if ($imported_object and not ref($imported_object)) {
                    # object requires sub-classsification in a way which involves different db data.
                    $re_iterate = 1;
                }
                push @imported, $imported_object;
            }
            $object = $imported[-1];
            
            if ($re_iterate) {
                # It is possible that one or more objects go into subclasses which require more
                # data than is on the results row.  For each subclass (or set of subclasses),
                # we make a more specific, subordinate iterator to delegate-to.
                $DB::single = 1;               
 
                # TODO: handle subclasses in other importers besides the primary one
                my $subclass_name = $object;

                # FIXME - this sidesteps the TODO issue mentioned above.  The resulting
                # behavior is that it will complete the main query, and then do individual
                # queries for all the resultant items that needed to be subclassed.  Correct
                # behavior, but not optimal
                #if (grep { not ref $_ } @imported[0..$#imported-1]) {
                #    #die "No support for sub-classifying joined objects yet!";
                #}
                unless (grep { not ref $_ } @imported[0..$#imported-1]) {
                
                    my $sub_iterator = $subordinate_iterator_for_class{$subclass_name};
                    unless ($sub_iterator) {
                        #print "parallel iteration for loading $subclass_name under $class_name!\n";
                        my $sub_classified_rule_template = $rule_template->sub_classify($subclass_name);
                        my $sub_classified_rule = $sub_classified_rule_template->get_rule_for_values(@values);
                        $sub_iterator 
                            = $subordinate_iterator_for_class{$subclass_name} 
                                = $self->_create_import_iterator_for_underlying_context($sub_classified_rule,$dsx);
                    }
                    ($object) = $sub_iterator->();
                    if (! defined $object) {
                        # the newly subclassed object 
                        redo;
                    }
                
                #unless ($object->id eq $id) {
                #    Carp::cluck("object id $object->{id} does not match expected id $id");
                #    $DB::single = 1;
                #    print "";
                #    die;
                #}
               }
            } # end of handling a possible subordinate iterator delegate
            
            unless ($object) {
                redo;
            }
            
            if ( (ref($object) ne $class_name) and (not $object->isa($class_name)) ) {
                $object = undef;
                redo;
            }
            
            if ($needs_further_boolexpr_evaluation_after_loading and not $rule->evaluate($object)) {
                $object = undef;
                redo;
            }
            
        }; # end of loop until we have a defined object to return
        
        return $object;
    };
    
    return $iterator;
}


sub _create_object_fabricator_for_loading_template {
    my ($self, $loading_template, $template_data, $rule, $rule_template, $values, $dsx) = @_;
    my @values = @$values;

    my $class_name                                  = $loading_template->{final_class_name};
    $class_name or die;
    
    my $class_meta                                  = $class_name->get_class_object;
    my $class_data                                  = $dsx->_get_class_data_for_loading($class_meta);
    my $class = $class_name;
    
    my $ghost_class                                 = $class_data->{ghost_class};
    my $sub_classification_meta_class_name          = $class_data->{sub_classification_meta_class_name};
    my $sub_classification_property_name            = $class_data->{sub_classification_property_name};
    my $sub_classification_method_name              = $class_data->{sub_classification_method_name};

    # FIXME, right now, we don't have a rule template for joined entities...
    
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
    
    my $rule_id = $rule->id;    
    my $rule_without_recursion_desc = $rule_template_without_recursion_desc->get_rule_for_values(@values);    
    
    my $loading_base_object;
    if ($loading_template == $template_data->{loading_templates}[0]) {
        $loading_base_object = 1;
    }
    else {
        $loading_base_object = 0;
        $needs_further_boolexpr_evaluation_after_loading = 0;
    }

    
    my %subclass_is_safe_for_re_bless;
    my %subclass_for_subtype_name;  
    my %recurse_property_value_found;
    
    my @property_names      = @{ $loading_template->{property_names} };
    my @id_property_names   = @{ $loading_template->{id_property_names} };
    my @column_positions    = @{ $loading_template->{column_positions} };
    my @id_positions        = @{ $loading_template->{id_column_positions} };
    my $multi_column_id     = (@id_positions > 1 ? 1 : 0);
    my $composite_id_resolver = $class_meta->get_composite_id_resolver;
    
    my %initial_object_data;
    if ($loading_template->{constant_property_names}) {
        my @constant_property_names  = @{ $loading_template->{constant_property_names} };
        my @constant_property_values = @{ $loading_template->{constant_property_values} };
        @initial_object_data{@constant_property_names} = @constant_property_values;
    }

    my $rule_class_name = $rule_template->subject_class_name;
    my $load_class_name = $class;
    # $rule can contain params that may not apply to the subclass that's currently loading.
    # get_rule_for_params() in array context will return the portion of the rule that actually applies
    my($load_rule, undef) = $load_class_name->get_rule_for_params($rule->params_list);
    my $load_rule_id = $load_rule->id;

    my @rule_properties_with_in_clauses =
        grep { $rule_template_without_recursion_desc->operator_for_property_name($_) eq '[]' } 
             $rule_template_without_recursion_desc->_property_names;

    #my $rule_template_without_in_clause = $rule_template_without_recursion_desc;
    my $rule_template_without_in_clause;
    if (@rule_properties_with_in_clauses) {
        my $rule_template_id_without_in_clause = $rule_template_without_recursion_desc->id;
        foreach my $property_name ( @rule_properties_with_in_clauses ) {
            # FIXME - removing and re-adding the filter should have the same effect as the substitute below,
            # but the two result in different rules in the end.
            #$rule_template_without_in_clause = $rule_template_without_in_clause->remove_filter($property_name);
            #$rule_template_without_in_clause = $rule_template_without_in_clause->add_filter($property_name);
            $rule_template_id_without_in_clause =~ s/($property_name) \[\]/$1/;
        }
        $rule_template_without_in_clause = UR::BoolExpr::Template->get($rule_template_id_without_in_clause);
    }

    my $object_fabricator = sub {
        my $next_db_row = $_[0];
        
        if ($loading_template != $template_data->{loading_templates}[0]) {
            # no handling for the non-primary class yet!
            #$DB::single = 1;
        }
        
        my $pending_db_object_data = { %initial_object_data };
        @$pending_db_object_data{@property_names} = @$next_db_row[@column_positions];
        
        # resolve id
        my $pending_db_object_id;
        if ($multi_column_id) {
            $pending_db_object_id = $composite_id_resolver->(@$pending_db_object_data{@id_property_names})
        }
        else {
            $pending_db_object_id = $pending_db_object_data->{$id_property_names[0]};
        }
        
        unless (defined $pending_db_object_id) {
            Carp::confess(
                "no id found in object data for $class_name?\n" 
                . Data::Dumper::Dumper($pending_db_object_data)
            );
        }
        
        my $pending_db_object;
        
        # skip if this object has been deleted but not committed
        do {
            no warnings;
            if ($UR::Object::all_objects_loaded->{$ghost_class}{$pending_db_object_id}) {
                return;
                #$pending_db_object = undef;
                #redo;
            }
        };

        # Handle the object based-on whether it is already loaded in the current context.
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
                for my $property (@property_names) {
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
            
            # TODO move up
            #if ($loading_base_object and not $rule_without_recursion_desc->evaluate($pending_db_object)) {
            #    # The object is changed in memory and no longer matches the query rule (= where clause)
            #    if ($loading_base_object and $rule_specifies_id) {
            #        $pending_db_object->{load}{param_key}{$class}{$rule_id}++;
            #        $UR::Object::all_params_loaded->{$class}{$rule_id}++;
            #    }
            #    $pending_db_object->signal_change('load');
            #    return;
            #    #$pending_db_object = undef;
            #    #redo;
            #}
            
        } # end handling objects which are already loaded
        else {
            # Handle the case in which the object is completely new in the current context.
            
            # Create a new object for the resultset row
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
                                    #print "skipping $some_subclass_name: no $subtype_name for $some_subclass_type_class\n";
                                }
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
                
                # note: we check this again with the real base class, but this keeps junk objects out of the core hash
                unless ($subclass_name->isa($class)) {
                    # We may have done a load on the base class, and not been able to use properties to narrow down to the correct subtype.
                    # The resultset returned more data than we needed, and we're filtering out the other subclasses here.
                    return;
                    #$pending_db_object = undef;
                    #redo; 
                }
            }
            else {
                # regular, non-subclassifier
                $subclass_name = $class;
            }
            
            # store the object
            # note that we do this on the base class even if we know it's going to be put into a subclass below
            $UR::Object::all_objects_loaded->{$class}{$pending_db_object_id} = $pending_db_object;
            #$pending_db_object->signal_change('create_object', $pending_db_object_id)
            
            # If we're using a light cache, weaken the reference.
            if ($UR::Context::light_cache and substr($class,0,5) ne 'App::') {
                Scalar::Util::weaken($UR::Object::all_objects_loaded->{$class_name}->{$pending_db_object_id});
            }
            
            # Make a note in all_params_loaded (essentially, the query cache) that we've made a
            # match on this rule, and some equivalent rules
            if ($loading_base_object and not $rule_specifies_id) {
                if ($rule_class_name ne $load_class_name) {
                    $pending_db_object->{load}{param_key}{$load_class_name}{$load_rule_id}++;
                    $UR::Object::all_params_loaded->{$load_class_name}{$load_rule_id}++;    
                }
                $pending_db_object->{load}{param_key}{$rule_class_name}{$rule_id}++;
                $UR::Object::all_params_loaded->{$rule_class_name}{$rule_id}++;

                if (@rule_properties_with_in_clauses) {
                    # FIXME - confirm that all the object properties are filled in at this point, right?
                    my @values = @$pending_db_object{@rule_properties_with_in_clauses};
                    #foreach my $property_name ( @rule_properties_with_in_clauses ) {
                    #    push @values, $pending_db_object->$property_name;
                    #}
                    my $r = $rule_template_without_in_clause->get_normalized_rule_for_values(@values);
                    
                    $UR::Object::all_params_loaded->{$rule_class_name}{$r->id}++;
                }
            }
            
            unless ($subclass_name eq $class) {
                # we did this above, but only checked the base class
                my $subclass_ghost_class = $subclass_name->ghost_class;
                if ($UR::Object::all_objects_loaded->{$subclass_ghost_class}{$pending_db_object_id}) {
                    return;
                    #$pending_db_object = undef;
                    #redo;
                }
                
                my $re_bless = $subclass_is_safe_for_re_bless{$subclass_name};
                if (not defined $re_bless) {
                    $re_bless = $dsx->_class_is_safe_to_rebless_from_parent_class($subclass_name, $class);
                    $re_bless ||= 0;
                    $subclass_is_safe_for_re_bless{$subclass_name} = $re_bless;
                }
                
                my $loading_info;
                if ($re_bless) {
                    # Performance shortcut.
                    # These need to be subclassed, but there is no added data to load.
                    # Just remove and re-add from the core data structure.
                    if (my $already_loaded = $subclass_name->is_loaded($pending_db_object->id)) {
                        if ($pending_db_object == $already_loaded) {
                            print "ALREADY LOADED SAME OBJ?\n";
                            $DB::single = 1;
                            die "The loaded object already exists in its target subclass?!";
                        }
                        
                        if ($loading_base_object) {
                            # Get our records about loading this object
                            $loading_info = $dsx->_get_object_loading_info($pending_db_object);
                            
                            # Transfer the load info for the load we _just_ did to the subclass too.
                            $loading_info->{$subclass_name} = $loading_info->{$class};
                            $loading_info = $dsx->_reclassify_object_loading_info_for_new_class($loading_info,$subclass_name);
                        }
                        
                        # This will wipe the above data from the object and the contex...
                        $pending_db_object->unload;
                        
                        if ($loading_base_object) {
                            # ...now we put it back for both.
                            $dsx->_add_object_loading_info($already_loaded, $loading_info);
                            $dsx->_record_that_loading_has_occurred($loading_info);
                        }
                        
                        $pending_db_object = $already_loaded;
                    }
                    else {
                        if ($loading_base_object) {
                            $loading_info = $dsx->_get_object_loading_info($pending_db_object);
                            $dsx->_record_that_loading_has_occurred($loading_info);
                            $loading_info->{$subclass_name} = delete $loading_info->{$class};
                            $loading_info = $dsx->_reclassify_object_loading_info_for_new_class($loading_info,$subclass_name);
                        }
                        
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
                else {
                    # This object cannot just be re-classified into a subclass because the subclass joins to additional tables.
                    # We'll make a parallel iterator for each subclass we encounter.
                    
                    # Note that we let the calling db-based iterator do that, so that if multiple objects on the row need 
                    # sub-classing, we do them all at once.
                    
                    # Decrement all of the param_keys it is using.
                    if ($loading_base_object) {
                        $loading_info = $dsx->_get_object_loading_info($pending_db_object);
                        $loading_info = $dsx->_reclassify_object_loading_info_for_new_class($loading_info,$subclass_name);
                    }
                    
                    $pending_db_object->unload;
                    
                    if ($loading_base_object) {
                        $dsx->_record_that_loading_has_occurred($loading_info);
                    }
                    
                    # NOTE: we're returning a class name instead of an object
                    # this tells the caller to re-do the entire row using a subclass to get the real data.
                    # Hack?  Probably so...
                    return $subclass_name;
                }
                
                # the object may no longer match the rule after subclassifying...
                if ($loading_base_object and not $rule->evaluate($pending_db_object)) {
                    #print "Object does not match rule!" . Dumper($pending_db_object,[$rule->params_list]) . "\n";
                    $DB::single = 1;
                    $rule->evaluate($pending_db_object);
                    $DB::single = 1;
                    $rule->evaluate($pending_db_object);
                    return;
                    #$pending_db_object = undef;
                    #redo;
                }
            } # end of sub-classification code
            
            # Signal that the object has been loaded
            # NOTE: until this is done indexes cannot be used to look-up an object
            #$pending_db_object->signal_change('load_external');
            $pending_db_object->signal_change('load');
        
            #$DB::single = 1;
            if (
                $loading_base_object
                and
                $needs_further_boolexpr_evaluation_after_loading 
                and 
                not $rule->evaluate($pending_db_object)
            ) {
                return;
                #$pending_db_object = undef;
                #redo;
            }
        } # end handling newly loaded objects
        
        # When there is recursion in the query, we record data from each 
        # recursive "level" as though the query was done individually.
        if ($recursion_desc and $loading_base_object) {
            # if we got a row from a query, the object must have
            # a db_committed or db_saved_committed                                
            my $dbc = $pending_db_object->{db_committed} || $pending_db_object->{db_saved_uncommitted};
            die 'No save info found in recursive data?' unless defined $dbc;
            
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
        } # end of handling recursion
            
        return $pending_db_object;
        
    }; # end of per-class object fabricator
    
    return $object_fabricator;
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
    
    my $id_only = $params->{_id_only};
    $id_only = undef if ref($id) and ref($id) eq 'HASH';
    if ($id_only) {
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

#    no warnings;

    my $loading_was_done_before_with_these_params =
            # complex (non-single-id) params
            exists($params->{_param_key}) 
            && (
                # exact match to previous attempt
                exists ($UR::Object::all_params_loaded->{$class}->{$params->{_param_key}})
                ||
                # this is a subset of a previous attempt
                ($self->_loading_was_done_before_with_a_superset_of_this_params_hashref($class,$params))
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
            my $index_id = UR::Object::Index->_resolve_composite_id($class,join(",",@properties));
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
            #return $index->get_objects_matching_rule($rule);  # Hrm bootstrapping doesn't work with this :(
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

    for my $try_class ( $class, $class->inheritance ) {
        # more than one property, see if individual checks have been done for any of these...
        for my $property_name (@property_names) {
            next unless ($try_class->get_class_object->get_property_meta_by_name($property_name));

            my $key = $try_class->get_rule_for_params($property_name => $params->{$property_name})->id;
            if (defined($key)
                && exists $all_params_loaded->{$try_class}->{$key}) {
                # DRY
                $all_params_loaded->{$try_class}->{$params->{_param_key}} = 1;
                my $new_key = $params->{_param_key};
                for my $obj ($try_class->all_objects_loaded) {
                    my $load_data = $obj->{load};
                    next unless $load_data;
                    my $param_key_data = $load_data->{param_key};
                    next unless $param_key_data;
                    my $class_data = $param_key_data->{$try_class};
                    next unless $class_data;
                    $class_data->{$new_key}++;
                }
                return 1;
            }
        }
        # No sense looking further up the inheritance
        # FIXME UR::ModuleBase is in the inheritance list, you can't call get_class_object() on it
        # and I'm having trouble getting a UR class object defined for it...
        last if ($try_class eq 'UR::Object'); 
    }
    return;   
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

    for (@changed_objects) {
        $_->signal_change("presync");
    }

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
        #$data_source = $data_source->class;        
        $ds_objects{$data_source} ||= { 'ds_obj' => $data_source, 'changed_objects' => []};
        push @{ $ds_objects{$data_source}->{'changed_objects'} }, $obj;
    }

    my @ds_in_order = 
        sort {
            ($a->{'ds_obj'}->can_savepoint <=> $b->{'ds_obj'}->can_savepoint)
            || 
            ($a->{'ds_obj'}->class cmp $b->{'ds_obj'}->class)
        }
        keys %ds_objects;

    # save on each in succession
    my @done;
    my $rollback_on_non_savepoint_handle;
    for my $data_source_string (@ds_in_order) {
        my $obj_list = $ds_objects{$data_source_string}->{'changed_objects'};

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

        my $data_source = $ds_objects{$data_source_string}->{'ds_obj'};
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
    $UR::Context::current = $UR::Context::process;
    
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
