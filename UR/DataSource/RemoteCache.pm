package UR::DataSource::RemoteCache;

use strict;
use warnings;

# FIXME  This is a bare-bones datasource and only supports read-only connections for now
# There's very minimal error checking.  Some duplication of code between here and
# UR::Service::DataSourceProxy.  The messaging protocol, connection details, etc
# probably need to be refactored into a more general RPC mechanism some time later
#
# In short, It's just here to remind people that it exists and needs to be
# cleaned up later.

require UR;

UR::Object::Type->define(
    class_name => 'UR::DataSource::RemoteCache',
    is => ['UR::DataSource'],
    english_name => 'ur datasource remotecache',
#    is_abstract => 1,
    properties => [
        host => {type => 'String', is_transient => 1},
        port => {type => 'String', is_transient => 1, default_value => 10293},
        socket => {type => 'IO::Socket', is_transient => 1},
    ],
    id_by => ['host','port'],
    doc => "A datasource representing a connection to another process",
);

# FIXME needs real pod docs.  In the mean time, here's how you'd create a program that just
# tells a class to get its data from some other server:
# use GSC;
# my $remote_ds = UR::DataSource::RemoteCache->create(host => 'localhost',port => 10293);
# my $class_object = UR::Object::Type->get(class_name => 'GSC::Clone');
# $class_object->data_source($remote_ds);
# @clones = GSC::Clone->get(10001);


use IO::Socket;

sub create {
    my $class = shift;
    my %params = @_;

    my $obj = $class->SUPER::create(@_);

    return unless $obj;

    unless ($obj->_connect_socket()) {
        $class->error_message(sprintf("Failed to connect to remote host %s:%s",
                                      $params{'host'}, $params{'port'}));
        return;
    }

    return $obj;
}

    

sub _connect_socket {
    my $self = shift;
    
    my $socket = IO::Socket::INET->new(PeerHost => $self->host,
                                       PeerPort => $self->port,
                                       ReuseAddr => 1,
                                       #ReusePort => 1,
                                     );
    unless ($socket) {
        $self->error_message("Couldn't connect to remote host: $!");
        return;
    }

    $self->socket($socket);

    $self->_init_created_socket();

    return 1;
}
                                       

sub _init_created_socket {
    # override in sub-classes
    1;
}


# old interface, the new entrypoint is create_iterator_closure_for_rule_template_and_values() below
#sub get_objects_for_rule {        
#    # This is the interface used by ::Object behind get()
#    my $self = shift;
#    
#    my @results = $self->_remote_get(@_);
#
#    return unless defined wantarray;
#    return @results if wantarray;
#    die "Multiple results unexpected" if @results > 1;
#    return $results[0];
#}

use FreezeThaw;
sub _remote_get_with_rule {
    my $self = shift;

$DB::single=1;
    my $string = FreezeThaw::freeze(\@_);
    my $socket = $self->socket;

    # First word is message length, second is command - 1 is "get"
    $socket->print(pack("LL", length($string),1),$string);

    my $cmd;
    ($string,$cmd) = $self->_read_message($socket);

    unless ($cmd == 129)  {
        $self->error_message("Got back unexpected command code.  Expected 129 got $cmd\n");
        return;
    }
      
    return unless ($string);  # An empty response
    
    my($result) = FreezeThaw::thaw($string);

    return @$result;
}
    
    
# This should be refactored into a messaging module later
sub _read_message {
    my $self = shift;
    my $socket = shift;

    my $buffer = "";
    my $read = $socket->sysread($buffer,8);
    if ($read == 0) {
        # The handle must be closed, or someone set it to non-blocking
        # and there's nothing to read
        return (undef, -1);
    }

    unless ($read == 8) {
        die "short read getting message length";
    }

    my($length,$cmd) = unpack("LL",$buffer);
    my $string = "";
    $read = $socket->sysread($string,$length);

    return($string,$cmd);
}
    


sub create_iterator_closure_for_rule {
    my ($self, $rule) = @_;

    $DB::single = 1;

    # FIXME make this more efficient so that we dispatch the request, and the
    # iterator can fetch one item back at a time
    my @results = $self->_remote_get_with_rule($rule);

    my $iterator = sub {
        my $items_to_return = $_[0] || 1;
     
        return unless @results;
        my @return = splice(@results,0, $items_to_return);

        return @return;
    };

    return $iterator;
}




#    my ($self, $rule_template, @values) = @_; 
#
#    my $template_data = $self->_get_template_data_for_loading($rule_template); 
#
#    #
#    # the template has general class data
#    #
#
#    my $ghost_class                                 = $template_data->{ghost_class};
#    my $class_name                                  = $template_data->{class_name};
#    my $class = $class_name;
#
#    my @parent_class_objects                        = @{ $template_data->{parent_class_objects} };
#    my @all_table_properties                        = @{ $template_data->{all_table_properties} };
#    my $first_table_name                            = $template_data->{first_table_name};
#    my $sub_classification_meta_class_name          = $template_data->{sub_classification_meta_class_name};
#    my $sub_classification_property_name            = $template_data->{sub_classification_property_name};
#    my $sub_classification_method_name              = $template_data->{sub_classification_method_name};
#
#    my @all_id_property_names                       = @{ $template_data->{all_id_property_names} };           
#    my @id_properties                               = @{ $template_data->{id_properties} };               
#    my $id_property_sorter                          = $template_data->{id_property_sorter};                    
#    
#    my $order_by_clause                             = $template_data->{order_by_clause};
#    
#    my @lob_column_names                            = @{ $template_data->{lob_column_names} };
#    my @lob_column_positions                        = @{ $template_data->{lob_column_positions} };
#    my @lob_column_positions                        = @{ $template_data->{lob_column_positions} };
#    
#    my $query_config                                = $template_data->{query_config}; 
#    my $post_process_results_callback               = $template_data->{post_process_results_callback};
#
#    my $sub_typing_property                         = $template_data->{sub_typing_property};
#    my $class_table_name                            = $template_data->{class_table_name};
#    my @type_names_under_class_with_no_table        = @{ $template_data->{type_names_under_class_with_no_table} };
#
#    #
#    # the template has explicit template data
#    #  
#
#    my $select_clause                              = $template_data->{select_clause};
#    my $select_hint                                = $template_data->{select_hint};
#    my $from_clause                                = $template_data->{from_clause};
#    my $where_clause                               = $template_data->{where_clause};
#    my $connect_by_clause                          = $template_data->{connect_by_clause};    
#    
#    my $sql_params                                  = $template_data->{sql_params};
#    my $filter_specs                                = $template_data->{filter_specs};
#    
#    my @property_names_in_resultset_order           = @{ $template_data->{property_names_in_resultset_order} };
#    my $properties_for_params                       = $template_data->{properties_for_params};
#    
#    my $rule_template_id                            = $template_data->{rule_template_id};
#    my $rule_template_without_recursion_desc        = $template_data->{rule_template_without_recursion_desc};
#    my $rule_template_id_without_recursion_desc     = $template_data->{rule_template_id_without_recursion_desc};
#    my $rule_matches_all                            = $template_data->{rule_matches_all};
#    my $rule_template_is_id_only                    = $template_data->{rule_template_is_id_only};
#    my $rule_specifies_id                           = $template_data->{rule_specifies_id};
#    my $rule_template_specifies_value_for_subtype   = $template_data->{rule_template_specifies_value_for_subtype};
#
#    my $recursion_desc                              = $template_data->{recursion_desc};
#    my $recurse_property_on_this_row                = $template_data->{recurse_property_on_this_row};
#    my $recurse_property_referencing_other_rows     = $template_data->{recurse_property_referencing_other_rows};
#
#    #
#    # if there is a property which specifies a sub-class for the objects, switch rule/values and call this again recursively
#    #
#
#    if (my $sub_typing_property) {
#        warn "Implement me carefully";
#        if ($rule_template_specifies_value_for_subtype) {
#            $DB::single = 1;           
#            my @values = @_;
#            my $rule = $rule_template->get_rule_for_values(@values);
#            my $value = $rule->specified_value_for_property_name($sub_typing_property);
#            my $type_obj = $sub_classification_meta_class_name->get($value);
#            if ($type_obj) {
#                my $subclass_name = $type_obj->subclass_name($class);
#                if ($subclass_name and $subclass_name ne $class) {
#                    $rule = $subclass_name->get_rule_for_params($rule->params_list, $sub_typing_property => $value);
#                    ($rule_template,@values) = $rule->get_rule_template_and_values();
#                    return $self->_create_iterator_closure_for_rule_template_and_values($rule_template,@values)
#                }
#            }
#            else {
#                die "No $value for $class?\n";
#            }
#        }
#        elsif (not $class_table_name) {
#            $DB::single = 1;
#            # we're in a sub-class, and don't have the type specified
#            # check to make sure we have a table, and if not add to the filter
#            my $rule = $class_name->get_rule_for_params(
#                $rule_template->get_rule_for_values(@values)->params_list, 
#                $sub_typing_property => (@type_names_under_class_with_no_table > 1 ? \@type_names_under_class_with_no_table : $type_names_under_class_with_no_table[0]),
#            );
#            my ($rule_template,@values) = $rule->get_rule_template_and_values();
#            return $self->_create_iterator_closure_for_rule_template_and_values($rule_template,@values)
#        }
#        else {
#            # continue normally
#            # the logic below will handle sub-classifying each returned entity
#        }
#    }
#
#
#    #
#    # gather the data specific to this group of values
#    # we don't cache these on the rule since a rule is typically only loaded once anyway
#    #
#
#    my $rule = $rule_template->get_rule_for_values(@values);
#    my $rule_id = $rule->id;
#    
#    my $rule_without_recursion_desc = $rule_template_without_recursion_desc->get_rule_for_values(@values);
#    
#    # TODO: we get 90% of the way to a full where clause in the template, but 
#    # actually have to build it here since ther is no way to say "in (?)" and pass an arrayref :( 
#    # It _is_ possible, however, to process all of the filter specs with a constant number of params.
#    # This would optimize the common case.   
#    my @all_sql_params = @$sql_params;
#    for my $filter_spec (@$filter_specs) {
#        my ($expr_sql, $operator, $value_position) = @$filter_spec;
#        my $value = $values[$value_position];
#        my ($more_sql, @more_params) = 
#            $self->_extend_sql_for_column_operator_and_value($expr_sql, $operator, $value);
#            
#        $where_clause .= ($where_clause ? "\nand " : ($recursion_desc ? "start with " : "where "));
#        
#        if ($more_sql) {
#            $where_clause .= $more_sql;
#            push @all_sql_params, @more_params;
#        }
#        else {
#            # error
#            return;
#        }
#    }
#
#    # The full SQL statement for the template, besides the filter logic, is built here.    
#    my $final_sql = "\nselect ";
#    if ($select_hint) {
#        $final_sql .= $select_hint . " ";
#    }
#    $final_sql .= $select_clause;
#    $final_sql .= "\nfrom $from_clause";
#    $final_sql .= "\n$where_clause" if length($where_clause);
#    $final_sql .= "\n$connect_by_clause" if $connect_by_clause;           
#    $final_sql .= "\n$order_by_clause"; 
#    
#    my $id = $rule->specified_value_for_id;
#        
#    # sort the objects in the $cached list the same way the sql query will sort them
#    my $cached = [ sort $id_property_sorter $class_name->_is_loaded($rule) ];
#
#    # the iterator may need subordinate iterators if the objects are subclassable
#    my %subclass_is_safe_for_re_bless; 
#    my %subordinate_rule_template_for_class;
#    my %subordinate_iterator_for_class;
#
#    # buffers for the iterator
#    my $next_object;
#    my $pending_db_object;
#    my $pending_db_object_data;
#    my $pending_cached_object;
#    my $next_db_row;
#    my $object;
#    my $rows = 0;       # number of rows the query returned
#
#    my $dbh = $self->get_default_dbh;    
#    my $sth = $dbh->prepare($final_sql,$query_config);
#    unless ($sth) {
#        $class->error_message("Failed to prepare SQL $final_sql\n" . $dbh->errstr . "\n");
#        Carp::confess($class->error_message);
#    }    
#    unless ($sth->execute(@all_sql_params)) {
#        $id =~ s/\t/\\t/g;
#        $class->error_message("Failed to execute SQL $final_sql\n" . $sth->errstr . "\n" . Dumper($id) . "\n" . Dumper(\@$sql_params) . "\n");
#        Carp::confess($class->error_message);
#    }    
#    
#    my %subclass_for_subtype_name;      # DRY below
#    my %recurse_property_value_found;   # keep track during recursion of branches we've visited
#    
#    my $iterator = sub {
#        # This is the number of items we're expected to return.
#        # It is 1 by default for iterators, and -1 for a basic get() which returns everything.
#        my $countdown = $_[0] || 1;
#        
#        my @return_objects;
#=pod
#        # This chunk of code presumes a lot, but is useful for placing an upper-limit on speed
#        # It makes objects fairly "close to the metal"
#        
#        while ($next_db_row = $sth->fetchrow_arrayref) {
#            $pending_db_object_data = {};
#            @$pending_db_object_data{@property_names_in_resultset_order} = @$next_db_row;    
#            my $pending_db_object_id = (@id_properties > 1)
#                ? $class->composite_id(@{$pending_db_object_data}{@id_properties})
#                : $pending_db_object_data->{$id_properties[0]};                
#            unless (defined $pending_db_object_id) {
#                Carp::confess(
#                    "no id found in object data?\n" 
#                    . Data::Dumper::Dumper($pending_db_object_data, \@id_properties)
#                );
#            }            
#            $pending_db_object = bless { %$pending_db_object_data, id => $pending_db_object_id }, $class;
#            $pending_db_object->{db_committed} = $pending_db_object_data;    
#            push @return_objects, $pending_db_object;
#        }
#        return @return_objects;
#    
#=cut    
#        
#        while ($countdown != 0) {
#            # This block is necessary because Perl only looks 2 levels up for closure pad members.
#            # It ensures the above variables hold their value in this closure
#            do {                
#                no warnings;
#                (
#                    $self, 
#                    $rule_template, 
#                    @values,
#                    $template_data,
#                    $ghost_class,
#                    $class_name,
#                    $class,
#                    @parent_class_objects,
#                    @all_table_properties,
#                    $first_table_name,
#                    $sub_classification_meta_class_name,
#                    $sub_classification_property_name,
#                    $sub_classification_method_name,
#                    @all_id_property_names,
#                    @id_properties,
#                    $id_property_sorter,
#                    $order_by_clause,
#                    @lob_column_names,
#                    @lob_column_positions,
#                    $query_config,
#                    $post_process_results_callback,
#                    $sub_typing_property,
#                    $class_table_name,
#                    @type_names_under_class_with_no_table,
#                    $recursion_desc,
#                    $recurse_property_on_this_row,
#                    $recurse_property_referencing_other_rows,
#                    $sql_params,
#                    $filter_specs,
#                    $properties_for_params,
#                    @property_names_in_resultset_order,
#                    $rule_template_id,
#                    $rule_template_without_recursion_desc,
#                    $rule_template_id_without_recursion_desc,
#                    $rule_matches_all,
#                    $rule_template_is_id_only,
#                    $rule_template_specifies_value_for_subtype,
#                    $rule_specifies_id,
#                    $rule,
#                    $rule_id,
#                    $rule_without_recursion_desc,
#                    %recurse_property_value_found,
#                    @all_sql_params,
#                    $final_sql,
#                    $id,
#                    $cached,
#                    %subclass_is_safe_for_re_bless,
#                    %subordinate_rule_template_for_class,
#                    %subordinate_iterator_for_class,
#                    $next_object,
#                    $pending_db_object,
#                    $pending_cached_object,
#                    $next_db_row,
#                    $object,
#                    $rows,
#                    $dbh,
#                    $sth,
#                    %subclass_for_subtype_name
#                )
#            };
#            
#            # handle getting new data from the data source as necessary
#            if (defined($sth) and !defined($pending_db_object)) {
#                
#                # this loop will redo when the data returned no longer matches the rule in the current STM
#                for (1) {
#                    $next_db_row = $sth->fetchrow_arrayref;
#                    
#                    unless ($next_db_row) {
#                        $sth->finish;
#                        $sth = undef;
#                        
#                        if ($rows == 0) {
#                            # if we got no data at all from the sql then we give a status
#                            # message about it and we update all_params_loaded to indicate
#                            # that this set of parameters yielded 0 objects
#                            
#                            if ($rule_template_is_id_only) {
#                                $UR::Object::all_objects_loaded->{$class}->{$id} = undef;
#                            }
#                            else {
#                                $UR::Object::all_params_loaded->{$class}->{$rule_id} = 0;
#                            }
#                        }
#                        elsif ($rows > 1) {
#                            if ($id and not ref($id)) {
#                                warn("Multiple rows were returned by SQL:\n$final_sql\nExtra data ignored.\n");
#                            }            
#                        }
#                        
#                        if ( $rule_matches_all ) {
#                            # No parameters.  We loaded the whole class.
#                            # Doing a load w/o a specific ID w/o custom SQL loads the whole class.
#                            # Set a flag so that certain optimizations can be made, such as 
#                            # short-circuiting future loads of this class.        
#                            $class->all_objects_are_loaded(1);        
#                        }
#                        
#                        if ($recursion_desc) {
#                            my @results = $class->is_loaded($rule_without_recursion_desc);
#                            $UR::Object::all_params_loaded->{$class}{$rule_without_recursion_desc->id} = scalar(@results);
#                            for my $object (@results) {
#                                $object->{load}{param_key}{$class}{$rule_without_recursion_desc->id}++;
#                            }
#                        }
#                        
#                        last; # $pending_db_object = undef; still
#                    } 
#                    
#                    # we count rows processed mainly for more concise sanity checking
#                    $rows++;
#                    
#                    # this handles things lik BLOBS, which have a special interface to get the 'real' data
#                    if ($post_process_results_callback) {
#                        $next_db_row = $post_process_results_callback->($next_db_row);
#                    }
#                    
#                    # this is used for automated re-testing against a private database
#                    $self->_CopyToAlternateDB($class,$dbh,$next_db_row) if ($ENV{'UR_TEST_FILLDB'});                                
#                    
#                    # translate column hash into a hash structured like our new object
#                    my $pending_db_object_data = {};
#                    @$pending_db_object_data{@property_names_in_resultset_order} = @$next_db_row;    
#                    
#                    # resolve id
#                    my $pending_db_object_id = (@id_properties > 1)
#                        ? $class->composite_id(@{$pending_db_object_data}{@id_properties})
#                        : $pending_db_object_data->{$id_properties[0]};                
#                    unless (defined $pending_db_object_id) {
#                        Carp::confess(
#                            "no id found in object data?\n" 
#                            . Data::Dumper::Dumper($pending_db_object_data, \@id_properties)
#                        );
#                    }
#                
#                    # skip if this object has been deleted but not committed
#                    if ($UR::Object::all_objects_loaded->{$ghost_class}{$pending_db_object_id}) {
#                        $pending_db_object = undef;
#                        redo;
#                    }
#                    
#                    # ensure that we're not remaking things which have already been loaded
#                    if ($pending_db_object = $UR::Object::all_objects_loaded->{$class}{$pending_db_object_id}) {
#                        # The object already exists.            
#                        my $dbsu = $pending_db_object->{db_saved_uncommitted};
#                        my $dbc = $pending_db_object->{db_committed};
#                        if ($dbsu) {
#                            # Update its db_saved_uncommitted snapshot.
#                            %$dbsu = (%$dbsu, %$pending_db_object_data);
#                        }
#                        elsif ($dbc) {
#                            for my $property (keys %$pending_db_object_data) {
#                                no warnings;
#                                if ($pending_db_object_data->{$property} ne $dbc->{$property}) {
#                                    # This has changed in the database since we loaded the object.
#                                    
#                                    # Ensure that none of the outside changes conflict with 
#                                    # any inside changes, then apply the outside changes.
#                                    if ($pending_db_object->{$property} eq $dbc->{$property}) {
#                                        # no changes to this property in the application
#                                        # update the underlying db_committed
#                                        $dbc->{$property} = $pending_db_object_data->{$property};
#                                        # update the regular state of the object in the application
#                                        $pending_db_object->$property($pending_db_object_data->{$property});
#                                    }
#                                    else {
#                                        # conflicting change!
#                                        Carp::confess(qq/
#                                            A change has occurred in the database for
#                                            $class property $property on object $pending_db_object->{id}
#                                            from '$dbc->{$property}' to '$pending_db_object_data->{$property}'.                                    
#                                            At the same time, this application has made a change to 
#                                            that value to $pending_db_object->{$property}.
#                
#                                            The application should lock data which it will update 
#                                            and might be updated by other applications. 
#                                        /);
#                                    }
#                                }
#                            }
#                            # Update its db_committed snapshot.
#                            %$dbc = (%$dbc, %$pending_db_object_data);
#                        }
#                        
#                        if ($dbc || $dbsu) {
#                            $self->debug_message("object was already loaded", 4);
#                        }
#                        else {
#                            # No db_committed key.  This object was "create"ed 
#                            # even though it existed in the database, and now 
#                            # we've tried to load it.  Raise an error.
#                            die "$class $pending_db_object_id has just been loaded, but it exists in the application as a new unsaved object!\n" . Dumper($pending_db_object) . "\n";
#                        }
#                        
#                        unless ($rule_without_recursion_desc->evaluate($pending_db_object)) {
#                            # The object is changed in memory and no longer matches the query rule (= where clause)
#                            unless ($rule_specifies_id) {
#                                $pending_db_object->{load}{param_key}{$class}{$rule_id}++;
#                                $UR::Object::all_params_loaded->{$class}{$rule_id}++;                    
#                            }
#                            $pending_db_object->signal_change('load');                        
#                            $pending_db_object = undef;
#                            redo;
#                        }
#                        
#                    } # end handling objects which are already loaded
#                    else {        
#                        # create a new object for the resultset row
#                        $pending_db_object = bless { %$pending_db_object_data, id => $pending_db_object_id }, $class;
#                        $pending_db_object->{db_committed} = $pending_db_object_data;    
#                        
#                        # determine the subclass name for classes which automatically sub-classify
#                        my $subclass_name;
#                        if (    
#                                ($sub_classification_meta_class_name or $sub_classification_method_name)
#                                and                                    
#                                (ref($pending_db_object) eq $class) # not already subclased  
#                        ) {
#                            if ($sub_classification_method_name) {
#                                $subclass_name = $class->$sub_classification_method_name($pending_db_object);
#                                unless ($subclass_name) {
#                                    Carp::confess(
#                                        "Failed to sub-classify $class using method " 
#                                        . $sub_classification_method_name
#                                    );
#                                }        
#                            }
#                            else {    
#                                #$DB::single = 1;
#                                # Group objects requiring reclassification by type, 
#                                # and catch anything which doesn't need reclassification.
#                                
#                                my $subtype_name = $pending_db_object->$sub_classification_property_name;
#                                
#                                $subclass_name = $subclass_for_subtype_name{$subtype_name};
#                                unless ($subclass_name) {
#                                    my $type_obj = $sub_classification_meta_class_name->get($subtype_name);
#                                    
#                                    unless ($type_obj) {
#                                        # The base type may give the final subclass, or an intermediate
#                                        # either choice has trade-offs, but we support both.
#                                        # If an intermediate subclass is specified, that subclass
#                                        # will join to a table with another field to indicate additional 
#                                        # subclassing.  This means we have to do this part the hard way.
#                                        # TODO: handle more than one level.
#                                        my @all_type_objects = $sub_classification_meta_class_name->get();
#                                        for my $some_type_obj (@all_type_objects) {
#                                            my $some_subclass_name = $some_type_obj->subclass_name($class);
#                                            unless (UR::Object::Type->get($some_subclass_name)->is_abstract) {
#                                                next;
#                                            }                
#                                            my $some_subclass_meta = $some_subclass_name->get_class_object;
#                                            my $some_subclass_type_class = 
#                                                            $some_subclass_meta->sub_classification_meta_class_name;
#                                            if ($type_obj = $some_subclass_type_class->get($subtype_name)) {
#                                                # this second-tier subclass works
#                                                last;
#                                            }       
#                                            else {
#                                                # try another subclass, and check the subclasses under it
#                                                print "skipping $some_subclass_name: no $subtype_name for $some_subclass_type_class\n";
#                                            }
#                                            print "";
#                                        }
#                                    }
#                                    
#                                    if ($type_obj) {                
#                                        $subclass_name = $type_obj->subclass_name($class);
#                                    }
#                                    else {
#                                        warn "Failed to find $class_name sub-class for type '$subtype_name'!";
#                                        $subclass_name = $class_name;
#                                    }
#                                    
#                                    unless ($subclass_name) {
#                                        Carp::confess(
#                                            "Failed to sub-classify $class using " 
#                                            . $type_obj->class
#                                            . " '" . $type_obj->id . "'"
#                                        );
#                                    }        
#                                    
#                                    $subclass_name->class;
#                                }
#                                $subclass_for_subtype_name{$subtype_name} = $subclass_name;
#                            }
#                            
#                            unless ($subclass_name->isa($class)) {
#                                # We may have done a load on the base class, and not been able to use properties to narrow down to the correct subtype.
#                                # The resultset returned more data than we needed, and we're filtering out the other subclasses here.
#                                $pending_db_object = undef;
#                                redo; 
#                            }
#                        }
#                        else {
#                            # regular, non-subclassifier
#                            $subclass_name = $class;
#                        }
#                        
#                        # store the object
#                        # note that we do this on the base class even if we know it's going to be put into a subclass below
#                        # TODO: refactor
#                        $UR::Object::all_objects_loaded->{$class}{$pending_db_object_id} = $pending_db_object;
#                        #$pending_db_object->signal_change('create_object', $pending_db_object_id);                        
#                        
#                        # If we're using a light cache, weaken the reference.
#                        if ($UR::Context::light_cache and substr($class,0,5) ne 'App::') {
#                            Scalar::Util::weaken($UR::Object::all_objects_loaded->{$class_name}->{$pending_db_object_id});
#                        }
#                        
#                        unless ($rule_specifies_id) {
#                            $pending_db_object->{load}{param_key}{$class}{$rule_id}++;
#                            $UR::Object::all_params_loaded->{$class}{$rule_id}++;    
#                        }
#                        
#                        unless ($subclass_name eq $class) {
#                            # we did this above, but only checked the base class
#                            my $subclass_ghost_class = $subclass_name->ghost_class;
#                            if ($UR::Object::all_objects_loaded->{$ghost_class}{$pending_db_object_id}) {
#                                $pending_db_object = undef;
#                                redo;
#                            }
#                            
#                            my $re_bless = $subclass_is_safe_for_re_bless{$subclass_name};
#                            if (not defined $re_bless) {
#                                $re_bless = $self->_class_is_safe_to_rebless_from_parent_class($subclass_name, $class);
#                                $re_bless ||= 0;
#                                $subclass_is_safe_for_re_bless{$subclass_name} = $re_bless;
#                            }
#                            if ($re_bless) {
#                                # Performance shortcut.
#                                # These need to be subclassed, but there is no added data to load.
#                                # Just remove and re-add from the core data structure.
#                                if (my $already_loaded = $subclass_name->is_loaded($pending_db_object->id)) {
#                                
#                                    if ($pending_db_object == $already_loaded) {
#                                        print "ALREADY LOADED SAME OBJ?\n";
#                                        $DB::single = 1;
#                                        print "";            
#                                    }
#                                    
#                                    my $loading_info = $self->_get_object_loading_info($pending_db_object);
#                                    
#                                    # Transfer the load info for the load we _just_ did to the subclass too.
#                                    $loading_info->{$subclass_name} = $loading_info->{$class};
#                                    $loading_info = $self->_reclassify_object_loading_info_for_new_class($loading_info,$subclass_name);
#                                    
#                                    # This will wipe the above data from the object and the contex...
#                                    $pending_db_object->unload;
#                                    
#                                    # ...now we put it back for both.
#                                    $self->_add_object_loading_info($already_loaded, $loading_info);
#                                    $self->_record_that_loading_has_occurred($loading_info);
#                                    
#                                    $pending_db_object = $already_loaded;
#                                }
#                                else {
#                                    my $loading_info = $self->_get_object_loading_info($pending_db_object);
#                                    $loading_info->{$subclass_name} = delete $loading_info->{$class};
#                                    
#                                    $loading_info = $self->_reclassify_object_loading_info_for_new_class($loading_info,$subclass_name);
#                                    
#                                    my $prev_class_name = $pending_db_object->class;
#                                    my $id = $pending_db_object->id;            
#                                    $pending_db_object->signal_change("unload");
#                                    delete $UR::Object::all_objects_loaded->{$prev_class_name}->{$id};
#                                    delete $UR::Object::all_objects_are_loaded->{$prev_class_name};
#                                    bless $pending_db_object, $subclass_name;
#                                    $UR::Object::all_objects_loaded->{$subclass_name}->{$id} = $pending_db_object;
#                                    $pending_db_object->signal_change("load");            
#                                    
#                                    $self->_add_object_loading_info($pending_db_object, $loading_info);
#                                    $self->_record_that_loading_has_occurred($loading_info);
#                                }
#                            }
#                            else
#                            {
#                                # This object cannot just be re-classified into a subclass because the subclass joins to additional tables.
#                                # We'll make a parallel iterator for each subclass we encounter.
#                                
#                                # Decrement all of the param_keys it is using.
#                                my $loading_info = $self->_get_object_loading_info($pending_db_object);
#                                $loading_info = $self->_reclassify_object_loading_info_for_new_class($loading_info,$subclass_name);
#                                my $id = $pending_db_object->id;
#                                $pending_db_object->unload;
#                                $self->_record_that_loading_has_occurred($loading_info);
#    
#                                my $sub_iterator = $subordinate_iterator_for_class{$subclass_name};
#                                unless ($sub_iterator) {
#                                    #print "parallel iteration for loading $subclass_name under $class!\n";
#                                    my $sub_classified_rule_template = $rule_template->sub_classify($subclass_name);
#                                    $sub_iterator 
#                                        = $subordinate_iterator_for_class{$subclass_name} 
#                                            = $self->_create_iterator_closure_for_rule_template_and_values($sub_classified_rule_template,@values);
#                                }
#                                ($pending_db_object) = $sub_iterator->();
#                                if (! defined $pending_db_object) {
#                                    # the newly subclassed object 
#                                    redo;
#                                }
#                                unless ($pending_db_object->id eq $id) {
#                                    Carp::confess("object id $pending_db_object->{id} does not match expected s");
#                                    $DB::single = 1;
#                                    print "";
#                                }
#                            }
#                            
#                            # the object may no longer match the rule after subclassifying...
#                            unless ($rule->evaluate($pending_db_object)) {
#                                #print "Object does not match rule!" . Dumper($pending_db_object,[$rule->params_list]) . "\n";
#                                $pending_db_object = undef;
#                                redo;
#                            }
#                            
#                        } # end of sub-classification code
#                        
#                        # Signal that the object has been loaded
#                        # NOTE: until this is done indexes cannot be used to look-up an object
#                        #$pending_db_object->signal_change('load_external');
#                        $pending_db_object->signal_change('load');                    
#                    }
#                    
#                    # When there is recursion in the query, we record data from each 
#                    # recursive "level" as though the query was done individually.
#                    if ($recursion_desc) {                    
#                        # if we got a row from a query, the object must have
#                        # a db_committed or db_saved_committed                                
#                        my $dbc = $pending_db_object->{db_committed} || $pending_db_object->{db_saved_uncommitted};
#                        die 'this should not happen' unless defined $dbc;
#                        
#                        my $value_by_which_this_object_is_loaded_via_recursion = $dbc->{$recurse_property_on_this_row};
#                        my $value_referencing_other_object = $dbc->{$recurse_property_referencing_other_rows};
#                        
#                        unless ($recurse_property_value_found{$value_referencing_other_object}) {
#                            # This row points to another row which will be grabbed because the query is hierarchical.
#                            # Log the smaller query which would get the hierarchically linked data directly as though it happened directly.
#                            $recurse_property_value_found{$value_referencing_other_object} = 1;
#                            # note that the direct query need not be done again
#                            my $equiv_params = $class->get_rule_for_params($recurse_property_on_this_row => $value_referencing_other_object);
#                            my $equiv_param_key = $equiv_params->get_normalized_rule_equivalent->id;                
#                            
#                            # note that the recursive query need not be done again
#                            my $equiv_params2 = $class->get_rule_for_params($recurse_property_on_this_row => $value_referencing_other_object, -recurse => $recursion_desc);
#                            my $equiv_param_key2 = $equiv_params2->get_normalized_rule_equivalent->id;
#                            
#                            # For any of the hierarchically related data which is already loaded, 
#                            # note on those objects that they are part of that query.  These may have loaded earlier in this
#                            # query, or in a previous query.  Anything NOT already loaded will be hit later by the if-block below.
#                            my @subset_loaded = $class->is_loaded($recurse_property_on_this_row => $value_referencing_other_object);
#                            $UR::Object::all_params_loaded->{$class}{$equiv_param_key} = scalar(@subset_loaded);
#                            $UR::Object::all_params_loaded->{$class}{$equiv_param_key2} = scalar(@subset_loaded);
#                            for my $pending_db_object (@subset_loaded) {
#                                $pending_db_object->{load}->{param_key}{$class}{$equiv_param_key}++;
#                                $pending_db_object->{load}->{param_key}{$class}{$equiv_param_key2}++;
#                            }
#                        }
#                        
#                        if ($recurse_property_value_found{$value_by_which_this_object_is_loaded_via_recursion}) {
#                            # This row was expected because some other row in the hierarchical query referenced it.
#                            # Up the object count, and note on the object that it is a result of this query.
#                            my $equiv_params = $class->get_rule_for_params($recurse_property_on_this_row => $value_by_which_this_object_is_loaded_via_recursion);
#                            my $equiv_param_key = $equiv_params->get_normalized_rule_equivalent->id;
#                            
#                            # note that the recursive query need not be done again
#                            my $equiv_params2 = $class->get_rule_for_params($recurse_property_on_this_row => $value_by_which_this_object_is_loaded_via_recursion, -recurse => $recursion_desc);
#                            my $equiv_param_key2 = $equiv_params2->get_normalized_rule_equivalent->id;
#                            
#                            $UR::Object::all_params_loaded->{$class}{$equiv_param_key}++;
#                            $UR::Object::all_params_loaded->{$class}{$equiv_param_key2}++;
#                            $pending_db_object->{load}->{param_key}{$class}{$equiv_param_key}++;
#                            $pending_db_object->{load}->{param_key}{$class}{$equiv_param_key2}++;                
#                        }
#                    }
#                    
#                }; # end of the block which gets the next db row (runs once unless it hits objects to skip)
#                
#            } # done handling need for another row on an open sth
#            
#            # get the next cached item if we don't have one pending
#            while (@$cached and !$pending_cached_object) {
#                $pending_cached_object = shift @$cached;
#            }
#            
#            # decide which pending object to return next
#            # both the cached list and the list from the database are sorted separately,
#            # we're merging these into one return stream here
#            my $comparison_result;
#            if ($pending_db_object && $pending_cached_object) {
#                $comparison_result = $id_property_sorter->($pending_db_object, $pending_cached_object);
#            }
#    
#            if (
#                $pending_db_object 
#                and $pending_cached_object 
#                and $comparison_result == 0 # $pending_db_object->id eq $pending_cached_object->id
#            ) {
#                # the database and the cache have the same object "next"
#                $next_object = $pending_cached_object;
#                $pending_cached_object = undef;
#                $pending_db_object = undef;
#            }
#            elsif (                
#                $pending_db_object
#                and (
#                    (!$pending_cached_object)
#                    or
#                    ($comparison_result < 0) # ($pending_db_object->id le $pending_cached_object->id) 
#                )
#            ) {
#                # db object is next to be returned
#                $next_object = $pending_db_object;
#                $pending_db_object = undef;
#            }
#            elsif (                
#                $pending_cached_object 
#                and (
#                    (!$pending_db_object)
#                    or 
#                    ($comparison_result > 0) # ($pending_db_object->id ge $pending_cached_object->id) 
#                )
#            ) {
#                # cached object is next to be returned
#                $next_object = $pending_cached_object;
#                $pending_cached_object = undef;
#            }
#            else {
#                # nothing pending in either queue
#                if ($sth) {
#                    Carp::confess("open sth?");
#                }
#                if (@$cached) {
#                    Carp::confess("cached data?");
#                }
#                $next_object = undef;
#            }
#            
#            last unless defined $next_object;
#            push @return_objects, $next_object;
#            $countdown--;
#        }
#        
#        return @return_objects;
#    }; # end of iterator closure
#    
#    return $iterator;
#}
#
## This allows the size of an autogenerated IN-clause to be adjusted.
## The limit for Oracle is 1000, and a bug requires that, in some cases
## we drop to 250.
#my $in_clause_size_limit = 250;        
#
## This method is used when generating SQL for a rule template, in the joins
## and also on a per-query basis to turn specific values into a where clause
#sub _extend_sql_for_column_operator_and_value {
#    my ($self, $expr_sql, $op, $val, $escape) = @_;
#
#    if ($op eq '[]' and not ref($val) eq 'ARRAY') {
#        $DB::single = 1;
#        $val = [];
#    }    
#
#    my $sql; 
#    my @sql_params;
#    
#    if ($op eq '' or $op eq '=' or $op eq 'eq') {
#        $sql .= $expr_sql;
#        if ($self->_value_is_null($val))
#        {
#            $sql = "$expr_sql is NULL";
#        }
#        else
#        {
#            $sql = "$expr_sql = ?";
#            push @sql_params, $val;
#        }        
#    }
#    elsif ($op eq '[]' or $op =~ /in/i) {
#        no warnings 'uninitialized';
#        unless (@$val)
#        {
#            # an empty list was passed-in.
#            # since "in ()", like "where 1=0", is self-contradictory,
#            # there is no data to return, and no SQL required
#            Carp::carp("Null in-clause passed to default_load_sql");
#            return;
#        }
#        
#        my @list = sort @$val;
#        my $has_null = ( (grep { length($_) == 0 } @list) ? 1 : 0);
#        my $wrap = ($has_null or @$val > $in_clause_size_limit ? 1 : 0);
#        my $cnt = 0;
#        $sql .= "\n(\n   " if $wrap;
#        while (my @set = splice(@list,0,$in_clause_size_limit))
#        {
#            $sql .= "\n   or " if $cnt++;
#            $sql .= $expr_sql;
#            $sql .= " in (" . join(",",map { "'$_'" } @set) . ")";
#        }
#        if ($has_null) {
#            $sql .= "\n  or $expr_sql is null"
#        }
#        $sql .= "\n)\n" if $wrap;
#    }       
#    elsif($op =~ /^(like|not like|in|not in|\<\>|\<|\>|\=|\<\=|\>\=)$/i ) {
#        # SQL operator.  Use this directly.
#        $sql .= "$expr_sql $op ?";
#        push @sql_params, $val;        
#        if($op =~ /like/i) {
#            $escape ||= '\\';
#            $sql .= " escape '" . $escape . "'";
#        }
#    } elsif($op =~ /^(ne|\!\=)$/i) {                
#        # Perlish inequality.  Special SQL to handle this.
#        if (not defined($val)) {
#            # ne undef =~ is not null
#            $sql .= "$expr_sql is not null";
#            pop @sql_params;
#        }
#        elsif ($op =~ /^(ne|\!\=)$/i) {
#            # ne $v =~ should match everything but $v, including nulls
#            # != is the same, and will rely on is_loaded to 
#            # filter out any cases where "hello" != "goodbye" returns
#            # but Perl wants to exclude the value because they match numerically.
#            $sql .= "( $expr_sql != ?" 
#                    .  " or $expr_sql is null)";                                                     
#            push @sql_params, $val;
#        }                                
#    } elsif ($op eq "between") {
#        $sql .= "$expr_sql $op ? and ?";
#        push @sql_params, @$val;
#    } else {
#        # Something else?
#        die "Unkown operator $op!";
#    }
#        
#    if (@sql_params > 256) {
#        Carp::confess("A bug in Oracle causes queries using > 256 placeholders to return incorrect results.");
#    }
#
#    return ($sql, @sql_params)
#}
#
#sub _value_is_null {
#    # this is a separate method since some databases, like Oracle, treat empty strings as null values
#    my ($self, $value) = @_;
#    return 1 if not defined $value;
#    return if not ref($value);
#    if (ref($value) eq 'HASH') {
#        if ($value->{operator} eq '=' or $value->{operator} eq 'eq') {
#            if (not defined $value->{value}) {
#                return 1;
#            }
#            else {
#                return;
#            }
#        }
#    }
#    return;
#}


sub _record_that_loading_has_occurred {    
    my ($self, $param_load_hash) = @_;
    no strict 'refs';
    foreach my $class (keys %$param_load_hash) {
        my $param_data = $param_load_hash->{$class};
        foreach my $param_string (keys %$param_data) {
            $UR::Object::all_params_loaded->{$class}{$param_string} ||=
                $param_data->{$param_string};
        }
    }
}

sub _first_class_in_inheritance_with_a_table {
    # This is called once per subclass and cached in the subclass from then on.
    my $self = shift;
    my $class = shift;
    $class = ref($class) if ref($class);


    unless ($class) {
        $DB::single = 1;
        Carp::confess("No class?");
    }
    my $class_object = $class->get_class_object;
    my $found = "";
    for ($class_object, $class_object->get_inherited_class_objects)
    {                
        if ($_->table_name)
        {
            $found = $_->class_name;
            last;
        }
    }
    #eval qq/
    #    package $class;
    #    sub _first_class_in_inheritance_with_a_table { 
    #        return '$found' if \$_[0] eq '$class';
    #        shift->SUPER::_first_class_in_inheritance_with_a_table(\@_);
    #    }
    #/;
    die "Error setting data in subclass: $@" if $@;
    return $found;
}

sub _class_is_safe_to_rebless_from_parent_class {
    my ($self, $class, $was_loaded_as_this_parent_class) = @_;
    my $fcwt = $self->_first_class_in_inheritance_with_a_table($class);
    die "No parent class with a table found for $class?!" unless $fcwt;
    return ($was_loaded_as_this_parent_class->isa($fcwt));
}


#sub _sync_database {
#    my $self = shift;
#    my %params = @_;
#    
#    my $changed_objects = delete $params{changed_objects};
#    my %objects_by_class_name;
#    for my $obj (@$changed_objects) {
#        my $class_name = ref($obj);
#        $objects_by_class_name{$class_name} ||= [];
#        push @{ $objects_by_class_name{$class_name} }, $obj;
#    }
#
#    my $dbh = $self->get_default_dbh;    
#
#    #
#    # Determine what commands need to be executed on the database
#    # to sync those changes, and categorize them by type and table.
#    #
#
#    # As we iterate through changes, keep track of all of the involved tables.
#    my %all_tables;      # $all_tables{$table_name} = $number_of_commands;
#    
#    # Make a hash for each type of command keyed by table name.
#    my %insert;          # $insert{$table_name} = [ $change1, $change2, ...];
#    my %update;          # $update{$table_name} = [ $change1, $change2, ...];
#    my %delete;          # $delete{$table_name} = [ $change1, $change2, ...];
#
#    # Make a master hash referencing each of the above.
#    # $explicit_commands_by_type_and_table{'insert'}{$table} = [ $change1, $change2 ...]
#    my %explicit_commands_by_type_and_table = (
#        'insert' => \%insert,
#        'update' => \%update,
#        'delete' => \%delete
#    );
#
#    # Build the above data structures.
#    {
#        no warnings;
#        for my $class_name (sort keys %objects_by_class_name) {
#            for my $obj (@{ $objects_by_class_name{$class_name} }) {
#                my @commands = $self->_default_save_sql_for_object($obj);
#                next unless @commands;
#                
#                for my $change (@commands)
#                {
#                    #$commands{$change} = $change;
#    
#                    # Example change:
#                    # { type => 'update', table_name => $table_name,
#                    # column_names => \@changed_cols, sql => $sql,
#                    # params => \@values, class => $table_class, id => $id };
#    
#                    # There are often multiple changes per object, espeically
#                    # when the object is spread across multiple tables because of
#                    # inheritance.  We classify each change by the table and
#                    # the class immediately associated with the table, even if
#                    # the class in an abstract parent class on the object.
#                    my $table_name = $change->{table_name};
#                    my $id = $change->{id};                    
#                    $all_tables{$table_name}++;
#                    my $table = UR::DataSource::RDBMS::Table->get(table_name => $table_name,
#                                                                  data_source => $self);                    
#                    
#                    if ($change->{type} eq 'insert')
#                    {
#                        push @{ $insert{$change->{table_name}} }, $change;
#                    }
#                    elsif ($change->{type} eq 'update')
#                    {
#                        push @{ $update{$change->{table_name}} }, $change;
#                    }
#                    elsif ($change->{type} eq 'delete')
#                    {
#                        push @{ $delete{$change->{table_name}} }, $change;
#                    }
#                    else
#                    {
#                        print "UNKNOWN COMMAND TYPE $change->{type} $change->{sql}\n";
#                    }
#                }
#            }
#        }
#    }
#
#    # Determine which tables require a lock;
#
#    my %tables_requiring_lock;
#    for my $table_name (keys %all_tables) {
#        my $table_object = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self);
#        if (my @bitmap_index_names = $table_object->bitmap_index_names) {
#            my $changes;
#            if ($changes = $insert{$table_name} or $changes = $delete{$table_name}) {
#                $tables_requiring_lock{$table_name} = 1;
#            }
#            elsif (not $tables_requiring_lock{$table_name}) {
#                $changes = $update{$table_name};
#                my @column_names = sort map { @{ $_->{column_names} } } @$changes;
#                my $last_column_name = "";
#                for my $column_name (@column_names) {
#                    next if $column_name eq $last_column_name;
#                    my $column_obj = UR::DataSource::RDBMS::TableColumn->get(
#                                                   data_source => $self,
#                                                   table_name => $table_name,
#                                                   column_name => $column_name,
#                                               );
#                    if ($column_obj->bitmap_index_names) {
#                        $tables_requiring_lock{$table_name} = 1;
#                        last;
#                    }
#                    $last_column_name = $column_name;
#                }
#            }
#        }
#    }
#
#    #
#    # Make a mapping of prerequisites for each command,
#    # and a reverse mapping of dependants for each command.
#    #
#
#    my %all_table_commands;
#    my %prerequisites;
#    my %dependants;
#
#    for my $table_name (keys %all_tables) {
#        my $table = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self);
#        
#        my @fk = $table->fk_constraints;
#
#        if ($insert{$table_name})
#        {
#            $all_table_commands{"insert $table_name"} = 1;
#        }
#
#        if ($update{$table_name})
#        {
#            $all_table_commands{"update $table_name"} = 1;
#        }
#
#        if ($delete{$table_name})
#        {
#            $all_table_commands{"delete $table_name"} = 1;
#        }
#
#        # Go through the constraints.
#        for my $fk (@fk)
#        {
#            my $r_table_name = $fk->r_table_name;
#            my $r_table = UR::DataSource::RDBMS::Table->get(table_name => $r_table_name, data_source => $self);
#            
#            # RULES:
#            # insert r_table_name       before insert table_name
#            # insert r_table_name       before update table_name
#            # delete table_name         before delete r_table_name
#            # update table_name         before delete r_table_name
#
#            if ($insert{$table_name} and $insert{$r_table_name})
#            {
#                $prerequisites{"insert $table_name"}{"insert $r_table_name"} = $fk;
#                $dependants{"insert $r_table_name"}{"insert $table_name"} = $fk;
#            }
#
#            if ($update{$table_name} and $insert{$r_table_name})
#            {
#                $prerequisites{"update $table_name"}{"insert $r_table_name"} = $fk;
#                $dependants{"insert $r_table_name"}{"update $table_name"} = $fk;
#            }
#
#            if ($delete{$r_table_name} and $delete{$table_name})
#            {
#                $prerequisites{"delete $r_table_name"}{"delete $table_name"} = $fk;
#                $dependants{"delete $table_name"}{"delete $r_table_name"} = $fk;
#            }
#
#            if ($delete{$r_table_name} and $update{$table_name})
#            {
#                $prerequisites{"delete $r_table_name"}{"update $table_name"} = $fk;
#                $dependants{"update $table_name"}{"delete $r_table_name"} = $fk;
#            }
#        }
#    }
#
#    #
#    # Use the above mapping to build an ordered list of general commands.
#    # Note that the general command is something like "insert EMPLOYEES",
#    # while the explicit command is an exact insert statement with params.
#    #
#
#    my @general_commands_in_order;
#    my %self_referencing_table_commands;
#
#    my %all_unresolved = %all_table_commands;
#    my $unresolved_count;
#    my $last_unresolved_count = 0;
#    my @ready_to_add = ();
#
#    while ($unresolved_count = scalar(keys(%all_unresolved)))
#    {
#        if ($unresolved_count == $last_unresolved_count)
#        {
#            # We accomplished nothing on the last iteration.
#            # We are in an infinite loop unless something is done.
#            # Rather than die with an error, issue a warning and attempt to
#            # brute-force the sync.
#
#            # Process something with minimal deps as a work-around.
#            my @ordered_by_least_number_of_prerequisites =
#                sort{ scalar(keys(%{$prerequisites{$a}})) <=>  scalar(keys(%{$prerequisites{$b}})) }
#                grep { $prerequisites{$_} }
#                keys %all_unresolved;
#
#            @ready_to_add = ($ordered_by_least_number_of_prerequisites[0]);
#            warn "Circular dependency! Pushing @ready_to_add to brute-force the save.\n";
#            print STDERR Dumper(\%objects_by_class_name, \%prerequisites, \%dependants) . "\n";
#        }
#        else
#        {
#            # This is the normal case.  It is either the first iteration,
#            # or we are on additional iterations with some progress made
#            # in the last iteration.
#
#            # Find commands which have no unresolved prerequisites.
#            @ready_to_add =
#                grep { not $prerequisites{$_} }
#                keys %all_unresolved;
#
#            # If there are none of the above, find commands
#            # with only self-referencing prerequisites.
#            unless (@ready_to_add)
#            {
#                # Find commands with only circular dependancies.
#                @ready_to_add =
#
#                    # The circular prerequisite must be the only prerequisite on the table.
#                    grep { scalar(keys(%{$prerequisites{$_}})) == 1 }
#
#                    # The prerequisite must be the same as the the table itself.
#                    grep { $prerequisites{$_}{$_} }
#
#                    # There must be prerequisites for the given table,
#                    grep { $prerequisites{$_} }
#
#                    # Look at all of the unresolved table commands.
#                    keys %all_unresolved;
#
#                # Note this for below.
#                # It records the $fk object which is circular.
#                for my $table_command (@ready_to_add)
#                {
#                    $self_referencing_table_commands{$table_command} = $prerequisites{$table_command}{$table_command};
#                }
#            }
#        }
#
#        # Record our current unresolved count for comparison on the next iteration.
#        $last_unresolved_count = $unresolved_count;
#
#        for my $db_command (@ready_to_add)
#        {
#            # Put it in the list.
#            push @general_commands_in_order, $db_command;
#
#            # Delete it from the main hash of command/table pairs
#            # for which dependencies are not resolved.
#            delete $all_unresolved{$db_command};
#
#            # Find anything which depended on this command occurring first
#            # and remove this command from that command's prerequisite list.
#            for my $dependant (keys %{ $dependants{$db_command} })
#            {
#                # Tell it to take us out of its list of prerequisites.
#                delete $prerequisites{$dependant}{$db_command} if $prerequisites{$dependant};
#
#                # Get rid of the prereq entry if it is empty;
#                delete $prerequisites{$dependant} if (keys(%{ $prerequisites{$dependant} }) == 0);
#            }
#
#            # Note that nothing depends on this command any more since it has been queued.
#            delete $dependants{$db_command};
#        }
#    }
#
#    # Go through the ordered list of general commands (ie "insert TABLE_NAME")
#    # and build the list of explicit commands.
#    my @explicit_commands_in_order;
#    for my $general_command (@general_commands_in_order)
#    {
#        my ($dml_type,$table_name) = split(/\s+/,$general_command);
#
#
#        if (my $circular_fk = $self_referencing_table_commands{$general_command})
#        {
#            # A circular foreign key requires that the
#            # items be inserted in a specific order.
#            my (@rcol) = $circular_fk->column_names;
#
#            # Get the IDs and objects which need to be saved.
#            my @cmds = @{ $explicit_commands_by_type_and_table{$dml_type}{$table_name} };
#            my @ids =  map { $_->{id} } @cmds;
#
##            my @objs = $cmds[0]->{class}->is_loaded(\@ids);
#            my $is_loaded_class = ($dml_type eq 'delete')
#                ? $cmds[0]->{class}->ghost_class
#                : $cmds[0]->{class};
#
#            my @objs = $is_loaded_class->is_loaded(\@ids);
#            my %objs = map { $_->id => $_ } @objs;
#
#            # Produce the explicit command list in dep order.
#            my %unsorted_cmds = map { $_->{id} => $_ } @cmds;
#            my $add;
#            my @local_explicit_commands;
#            $add = sub {
#                my ($cmd) = @_;
#                my $obj = $objs{$cmd->{id}};
#                my $pid = $obj->class->composite_id(map { $obj->$_ } @rcol);
#                if (defined $pid) {   # This recursive foreign key dep may have been optional
#                    my $pcmd = delete $unsorted_cmds{$pid};
#                    $add->($pcmd) if $pcmd;
#                }
#                push @local_explicit_commands, $cmd;
#            };
#            for my $cmd (@cmds) {
#                next unless $unsorted_cmds{$cmd->{id}};
#                $add->(delete $unsorted_cmds{$cmd->{id}});
#            }
#
#            if ($dml_type eq 'delete') {
#                @local_explicit_commands =
#                    reverse @local_explicit_commands;
#            }
#
#            push @explicit_commands_in_order, @local_explicit_commands;
#        }
#        else
#        {
#            # Order is irrelevant on non-self-referencing tables.
#            push @explicit_commands_in_order, @{ $explicit_commands_by_type_and_table{$dml_type}{$table_name} };
#        }
#    }
#
#    my %table_objects_by_class_name;
#    my %column_objects_by_class_and_column_name;
#
#    # Make statement handles.
#    # my $dbh = App::DB->dbh;
#    my %sth;
#    for my $cmd (@explicit_commands_in_order)
#    {
#        my $sql = $cmd->{sql};
#
#        unless ($sth{$sql})
#        {
#            my $class_name = $cmd->{class};
#
#            # get the db handle to use for this class
#            my $dbh = $class_name->dbh;
#            my $sth = $dbh->prepare($sql);
#            $sth{$sql} = $sth;
#
#            if ($dbh->errstr)
#            {
#                $self->error_message("Error preparing SQL:\n$sql\n" . $dbh->errstr . "\n");
#                return;
#            }
#            
#            my $tables = $table_objects_by_class_name{$class_name};
#            my $class_object = $class_name->get_class_object;
#            unless ($tables) {                
#                my $tables;
#                my @all_table_names = $class_object->all_table_names;                
#                for my $table_name (@all_table_names) {                    
#                    my $table = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self);
#                    push @$tables, $table;
#                    $column_objects_by_class_and_column_name{$class_name} ||= {};             
#                    my $columns = $column_objects_by_class_and_column_name{$class_name};
#                    unless (%$columns) {
#                        for my $column ($table->columns) {
#                            $columns->{$column->column_name} = $column;
#                        }
#                    }
#                }
#                $table_objects_by_class_name{$class_name} = $tables;
#            }
#
#            my @column_objects = 
#                map {
#                    my $column = $column_objects_by_class_and_column_name{$class_name}{$_};
#                    unless ($column) {
#                        print "looking at parent classes for $class_name\n";
#			for my $ancestor_class_name ($class_object->ordered_inherited_class_names) {
#	                    $column = $column_objects_by_class_and_column_name{$ancestor_class_name}{$_};
#                            if ($column) {
#		                $column_objects_by_class_and_column_name{$class_name}{$_} = $column;
#        	                last;
#                            }
#			}
#                        unless ($column) {
#                            $DB::single = 1;
#                            die "Failed to find a column object column $_ for class $class_name";
#                        }
#                    }
#                    $column;
#                }
#                @{ $cmd->{column_names} };
#
#            # print "Column Types: @column_types\n";
#
#            for my $n (0 .. $#column_objects) {
#                if ($column_objects[$n]->data_type eq 'BLOB')
#                {
#                    $sth->bind_param($n+1, undef, { ora_type => 113,  ora_field => $column_objects[$n]->column_name });
#                }
#            }
#        }
#    }
#
#    # Set a savepoint if possible.
#    my $savepoint;
#    if ($self->can_savepoint) {
#        $savepoint = $self->_last_savepoint;
#        if ($savepoint) {
#            $savepoint++;
#        }
#        else {
#            $savepoint=1;
#        }
#        my $sp_name = "sp".$savepoint;
#        unless ($self->set_savepoint($sp_name)) {
#            $self->error_message("Failed to set a savepoint on "
#                . $self->class
#                . ": "
#                . $dbh->errstr
#            );
#            return;
#        }
#        $self->_last_savepoint($savepoint);
#    }
#    else {
#        # FIXME SQLite dosen't support savepoints, but autocommit is already off so this dies?!
#        #$dbh->begin_work;
#    }
#
#    # Do any explicit table locking necessary.
#    if (my @tables_requiring_lock = sort keys %tables_requiring_lock) {
#        $self->debug_message("Locking tables: @tables_requiring_lock.");
#        my $max_failed_attempts = 10;
#        for my $table_name (@tables_requiring_lock) {
#            my $dbh = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self)->dbh;
#            my $sth = $dbh->prepare("lock table $table_name in exclusive mode");
#            my $failed_attempts = 0;
#            my @err;
#            for (1) {
#                unless ($sth->execute) {
#                    $failed_attempts++;
#                    $self->warning_message(
#                        "Failed to lock $table_name (attempt # $failed_attempts): "
#                        . $sth->errstr
#                    );
#                    push @err, $sth->errstr;
#                    unless ($failed_attempts >= $max_failed_attempts) {
#                        redo;
#                    }
#                }
#            }
#            if ($failed_attempts > 1) {
#                my $err = join("\n",@err);
#                App::Mail->mail(
#                    To => 'autobulk@watson.wustl.edu',
#                    From => App->prog_name . ' <autobulk@watson.wustl.edu>',
#                    Subject => (
#                            $failed_attempts >= $max_failed_attempts
#                            ? "sync_database lock failure after $failed_attempts attempts"
#                            : "sync_database lock success after $failed_attempts attempts"
#                        )
#                        . " in " . App->prog_name
#                        . " on $table_name",
#                    Message => qq/
#                        $failed_attempts attempts to lock table $table_name
#
#                        Errors:
#                        $err
#
#                        The complete table lock list for this sync:
#                        @tables_requiring_lock
#                    /
#                );
#                if ($failed_attempts >= $max_failed_attempts) {
#                    $self->error_message(
#                        "Could not obtain an exclusive table lock on table "
#                        . $table_name . " after $failed_attempts attempts"
#                    );
#                    App::DB->pop_savepoint;
#                    return;
#                }
#            }
#        }
#    }
#
#    # Execute the commands in the correct order.
#
#    my @failures;
#    my $last_failure_count = 0;
#    my @previous_failure_sets;
#
#    # If there are failures, we fall-back to brute force and send
#    # a message to support to debug the inefficiency.
#    my $skip_fault_tolerance_check = 1;
#
#    for (1) {
#        @failures = ();
#        for my $cmd (@explicit_commands_in_order) {
#            unless ($sth{$cmd->{sql}}->execute(@{$cmd->{params}}))
#            {
#                my $dbh = $cmd->{class}->dbh;
#                push @failures, {cmd => $cmd, error_message => $dbh->errstr};
#                last if $skip_fault_tolerance_check;
#            }
#            $sth{$cmd->{sql}}->finish();
#        }
#
#        if (@failures) {
#            # There have been some failures.  In case the error has to do with
#            # a failure to correctly determine dependencies in the code above,
#            # we will retry the set of failed commands.  This repeats as long
#            # as some progress is made on each iteration.
#            if ( (@failures == $last_failure_count) or $skip_fault_tolerance_check) {
#                # We've tried this exact set of comands before and failed.
#                # This is a real error.  Stop retrying and report.
#                for my $error (@failures)
#                {
#                    $self->error_message("Error executing SQL:\n$error->{cmd}{sql}\n" . $error->{error_message} . "\n");
#                }
#                last;
#            }
#            else {
#                # We've failed, but we haven't retried this exact set of commands
#                # and found the exact same failures.  This is either the first failure,
#                # or we had failures before and had success on the last brute-force
#                # approach to sorting commands.  Try again.
#                push @previous_failure_sets, \@failures;
#                @explicit_commands_in_order = map { $_->{cmd} } @failures;
#                $last_failure_count = scalar(@failures);
#                $self->warning_message("RETRYING SAVE");
#                redo;
#            }
#        }
#    }
#
#    # Rollback to savepoint if there are errors.
#    if (@failures) {
#        if ($savepoint eq "NONE") {
#            # A failure on a database which does not support savepoints.
#            # We must rollback the entire transacation.
#            # This is only a problem for a mixed raw-sql and UR::Object environment.
#            $dbh->rollback;
#        }
#        else {
#            $self->_reverse_sync_database();
#        }
#        # Return false, indicating failure.
#        return;
#    }
#
#    unless ($self->_set_specified_objects_saved_uncommitted($changed_objects)) {
#        Carp::confess("Error setting objects to a saved state after sync_database.  Exiting.");
#        return;
#    }
#    
#    if (exists $params{'commit_on_success'} and ($params{'commit_on_success'} eq '1')) {
#        # Commit the current transaction.
#        # The handles will automatically update their objects to 
#        # a committed state from the one set above.
#        # It will throw an exception on failure.
#        $dbh->commit;
#    }
#
#    # Though we succeeded, see if we had to use the fault-tolerance code to
#    # do so, and warn software support.  This should never occur.
#    if (@previous_failure_sets) {
#        my $msg = "Dependency failure saving: " . Dumper(\@explicit_commands_in_order)
#                . "\n\nThe following error sets were produced:\n"
#                . Dumper(\@previous_failure_sets) . "\n\n" . Carp::cluck . "\n\n";
#
#        $self->warning_message($msg);
#        App::Mail->mail(
#            To => UR::Context::Process->support_email,
#            Subject => 'sync_database dependency sort failure',
#            Message => $msg
#        ) or $self->warning_message("Failed to send error email!");
#    }
#
#    return 1;
#}
#
#sub _reverse_sync_database {
#    my $self = shift;
#
#    unless ($self->can_savepoint) {
#        # This will not respect manual DML
#        # Developers must not use this back door on non-savepoint databases.
#        $self->get_default_dbh->rollback;
#        return "NONE";
#    }
#
#    my $savepoint = $self->_last_savepoint;
#    unless ($savepoint) {
#        Carp::confess("No savepoint set!");
#    }
#
#    my $sp_name = "sp".$savepoint;
#    unless ($self->rollback_to_savepoint($sp_name)) {
#        $self->error_message("Error removing savepoint $savepoint " . $self->get_default_dbh->errstr);
#        return 1;
#    }
#
#    $self->_last_savepoint(undef);
#    return $savepoint;
#}



#sub _get_current_entities {
#    my $self = shift;
#    my @class_meta = UR::Object::Type->is_loaded(
#        data_source => $self->id
#    );
#    my @objects;
#    for my $class_meta (@class_meta) {
#        next unless $class_meta->generated();  # Ungenerated classes won't have any instances
#        my $class_name = $class_meta->class_name;
#        push @objects, $class_name->all_objects_loaded();
#    }
#    return @objects;
#}
#
#
#sub _set_all_objects_saved_committed {
#    # called by UR::DBI on commit
#    my $self = shift;
#    my @objects = $self->_get_current_entities;        
#    for my $obj (@objects)  {
#        unless ($self->_set_object_saved_committed($obj)) {
#            die "An error occurred setting " . $obj->display_name_full 
#             . " to match the committed database state.  Exiting...";
#        }
#    }
#}
#
#sub _set_object_saved_committed {
#    # called by the above, and some test cases
#    my ($self, $object) = @_;
#    if ($object->{db_saved_uncommitted}) {
#        if ($object->isa("UR::Object::Ghost")) {
#            $object->signal_change("commit");
#            $object->delete_object;
#        }
#        else {
#            %{ $object->{db_committed} } = (
#                ($object->{db_committed} ? %{ $object->{db_committed} } : ()),
#                %{ $object->{db_saved_uncommitted} }
#            );
#            delete $object->{db_saved_uncommitted};
#            $object->signal_change("commit");
#        }
#    }
#    return $object;
#}
#
#sub _set_all_objects_saved_rolled_back {
#    # called by UR::DBI on commit
#    my $self = shift;
#    $DB::single = 1;
#    my @objects = $self->_get_current_entities;        
#    for my $obj (@objects)  {
#        unless ($self->_set_object_saved_rolled_back($obj)) {
#            die "An error occurred setting " . $obj->display_name_full 
#             . " to match the rolled-back database state.  Exiting...";
#        }
#    }
#}
#
#sub _set_object_saved_rolled_back {
#    # called by the above, and some test cases    
#    my ($self,$object) = @_;
#    delete $object->{db_saved_uncommitted};
#    return $object;
#}
#
#
#sub _do_on_default_dbh {
#    my $self = shift;
#    my $method = shift;
#
#    return 1 unless $self->has_default_dbh();
#
#    my $dbh = $self->get_default_dbh;
#    unless ($dbh->$method(@_)) {
#        $self->error_message("DataSource ",$self->get_name," failed to $method: ",$dbh->errstr);
#        return undef;
#    }
#
#    return 1;
#}
#
#sub commit {
#    my $self = shift;
#    $self->_do_on_default_dbh('commit', @_);
#}
#
#sub rollback {
#    my $self = shift;
#    $self->_do_on_default_dbh('rollback', @_);
#}
#
#sub disconnect {
#    my $self = shift;
#    $self->_do_on_default_dbh('disconnect', @_);
#}
#
#
#sub resolve_dbix_schema_name {
#    my $self = shift;
#
#    my @schema_parts = split(/::/, ref($self) ? $self->class_name : $self);
#    # This will be something like namespace::DataSource::name, change it to namespace::DBIx::name
#    $schema_parts[1] = 'DBIx';
#    my $schema_name = join('::',@schema_parts);
#
#    return $schema_name;
#}
#
#
#sub get_dbix_schema {
#    my $self = shift;
#
#    my $schema_name = $self->resolve_dbix_schema_name();
#
#    eval "use $schema_name;";
#
##    require DBIx::Class::Schema;
##
##    my $schema_isa = $schema_name . '::ISA';
##    { no strict 'refs';
##      @$schema_isa = ('DBIx::Class::Schema');
##    }
##
##    $schema_name->load_classes();
#
#    return $schema_name->connect($self->_dbi_connect_args);
#}
#

    


1;
