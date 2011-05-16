package UR::DataSource::QueryPlan;
use strict;
use warnings;
use UR;

# this class is an evolving attempt to formalize
# the blob of cached value used for query construction

class UR::DataSource::QueryPlan {
    is => 'UR::Value',
    id_by => [ 
        rule_template => { is => 'UR::BoolExpr::Template', id_by => ['subject_class_name','logic_type','logic_detail','constant_values_id'] }, 
        data_source   => { is => 'UR::DataSource', id_by => 'data_source_id' },
    ],
    has_transient => [
        _is_initialized => { is => 'Boolean' },
    
        _object_joins   => { is => 'SCALAR' },
        _sql_joins      => { is => 'ARRAY' },
        _sql_filters    => { is => 'ARRAY' },
        _sql_params     => { is => 'ARRAY' },
        
        lob_column_names                            => {},
        lob_column_positions                        => {},
        query_config                                => {},
        post_process_results_callback               => {},
        
        select_clause                               => {},
        select_hint                                 => {},
        from_clause                                 => {},
        where_clause                                => {},
        connect_by_clause                           => {},
        group_by_clause                             => {},
        order_by_columns                            => {},
       
        sql_params                                  => {},
        filter_specs                                => {},
        
        property_names_in_resultset_order           => {},

        rule_template_id                            => {},
        rule_template_id_without_recursion_desc     => {},
        rule_template_without_recursion_desc        => {},

        joins                                       => {},
        recursion_desc                              => {},
        recurse_property_referencing_other_rows     => {},
        
        needs_further_boolexpr_evaluation_after_loading => { is => 'Boolean' },
        joins_across_data_sources                   => {}, # context _resolve_query_plan_for_ds_and_bxt
        loading_templates                           => {},
        class_name                                  => {},
        rule_matches_all                            => {},
        rule_template_is_id_only                    => {},

        sub_typing_property                         => {},
        class_table_name                            => {},
        rule_template_specifies_value_for_subtype   => {},
        sub_classification_meta_class_name          => {},
    ]
};

# these hash keys are probably removable
# because they are not above, they will be deleted if _init sets them
# this exists primarily as a cleanup target list
my @extra = qw(
    id_properties
    direct_table_properties
    all_table_properties
    sub_classification_method_name
    subclassify_by
    properties_meta_in_resultset_order
    all_properties
    rule_specifies_id
    recurse_property_on_this_row
    all_id_property_names
    id_property_sorter
    properties_for_params
    first_table_name
    base_joins
    parent_class_objects
);

sub _init {
    my $self = shift;
  
    Carp::confess("already initialized???") if $self->_is_initialized;

    # Once all callers are using the API for this we won't need "_init".
    $self->_init_core();

    # We could have this sub-classify by data source type, but right
    # now it's conditional logic because we'll likely remove the distinctions.
    # This will work because we'll separate out the ds-specific portion
    # and call methods on the DS to get that part.
    my $ds = $self->data_source;
    $self->_init_rdbms() if $ds->isa("UR::DataSource::RDBMS");
    $self->_init_default() if $ds->isa("UR::DataSource::Default");
    $self->_init_remote_cache() if $ds->isa("UR::DataSource::RemoteCache");

    # This object is currently still used as a hashref, but the properties
    # are a declaration of the part of the hashref data we are still dependent upon.
    # This removes the other properties to ensure this is the case.
    # Next steps are to clean up the code below to not produce the data,
    # then this loop can throw an exception if extra untracked data is found.
    for my $key (keys %$self) {
        next if $self->can($key);
        delete $self->{$key};
    }

    $self->_is_initialized(1);
    return $self;
}

sub _init_rdbms {
    my $self = shift;
    my $rule_template = $self->rule_template;
    my $ds = $self->data_source;

    # class-based values
    my $class_name = $rule_template->subject_class_name;
    my $class_meta = $class_name->__meta__;
    my $class_data = $ds->_get_class_data_for_loading($class_meta);       

    # an array of arrays, containing $table_name, $column_name, $alias, $object_num
    # as joins are done we extend this, and then condense it into object fabricators
    my @all_table_properties                = @{ $class_data->{all_table_properties} };    

    my @parent_class_objects                = @{ $class_data->{parent_class_objects} };
    my @all_id_property_names               = @{ $class_data->{all_id_property_names} };
    my @id_properties                       = @{ $class_data->{id_properties} };   
    my $order_by_columns                    = $class_data->{order_by_columns} || [];
    
    #my $first_table_name                    = $class_data->{first_table_name};
    
    #my $id_property_sorter                  = $class_data->{id_property_sorter};    
    #my @lob_column_names                    = @{ $class_data->{lob_column_names} };
    #my @lob_column_positions                = @{ $class_data->{lob_column_positions} };
    #my $query_config                        = $class_data->{query_config}; 
    #my $post_process_results_callback       = $class_data->{post_process_results_callback};
    #my $class_table_name                    = $class_data->{class_table_name};

    # individual template based
    my $hints    = $rule_template->hints;
    my $order_by = $rule_template->order_by;
    my $group_by = $rule_template->group_by;
    my $page     = $rule_template->page;
    my $limit    = $rule_template->limit;
    my $aggregate = $rule_template->aggregate;
    my $recursion_desc = $rule_template->recursion_desc;

    my %group_by_property_names;
    if ($group_by) {
        # we only pull back columns we're grouping by or aggregating if there is grouping happening
        for my $name (@$group_by) {
            unless ($class_name->can($name)) {
                Carp::croak("Cannot group by '$name': Class $class_name has no property/method by that name");
            }
            $group_by_property_names{$name} = 1;
        }
        for my $data (@all_table_properties) {
            my $name = $data->[1]->property_name;
            if ($group_by_property_names{$name}) {
                $group_by_property_names{$name} = $data;
            }
        }
        @all_table_properties = grep { ref($_) } values %group_by_property_names; 
    }

    my %order_by_property_names;
    if ($order_by) {
        # we only pull back columns we're ordering by if there is ordering happening
        for my $name (@$order_by) {
            unless ($class_name->can($name)) {
                Carp::croak("Cannot order by '$name': Class $class_name has no property/method by that name");
            }
            $order_by_property_names{$name} = 1;
        }
        for my $data (@all_table_properties) {
            my $name = $data->[1]->property_name;
            if ($order_by_property_names{$name}) {
                $order_by_property_names{$name} = $data;
            }
        }
    }


    # _usually_ items freshly loaded from the DB don't need to be evaluated through the rule
    # because the SQL gets constructed in such a way that all the items returned would pass anyway.
    # But in certain cases (a delegated property trying to match a non-object value (which is a bug
    # in the caller's code from one point of view) or with calculated non-sql properties, then the
    # sql will return a superset of the items we're actually asking for, and the loader needs to
    # validate them through the rule
    my $needs_further_boolexpr_evaluation_after_loading;

    my ($first_table_name, @sql_joins) =  _resolve_db_joins_for_inheritance($class_meta);
   
    my @sql_filters; 
    my @delegated_properties;    

    do { 
        
        my %filters =     
            map { $_ => 0 }
            grep { substr($_,0,1) ne '-' }
            $rule_template->_property_names;
        
        unless (@all_id_property_names == 1 && $all_id_property_names[0] eq "id") {
            delete $filters{'id'};
        }

        my %properties_involved = map { $_ => 1 }
                                    keys(%filters),
                                    ($hints ? @$hints : ()),
                                    ($order_by ? @$order_by : ()),
                                    ($group_by ? @$group_by : ());
        
        my @properties_involved = sort keys(%properties_involved);
        my @errors;
        while (my $property_name = shift @properties_involved) {
            my (@pmeta) = $class_meta->property_meta_for_name($property_name);
            unless (@pmeta) {
                push @errors, "No value position found in rule template for filter property $property_name?!"
                    . Data::Dumper::Dumper($rule_template);
                next;
            }
            
            if (index($property_name,'.') != -1) {
                push @delegated_properties, $property_name;
                next;
            }
            
            my $property = $pmeta[0];
            my $table_name = $property->class_meta->table_name;
            my $operator       = $rule_template->operator_for($property_name);
            my $value_position = $rule_template->value_position_for_property_name($property_name);

            if ($property->can("expr_sql")) {
                unless ($table_name) {
                    $ds->warning_message("Property '$property_name' of class '$class_name' can 'expr_sql' but has no table!");
                    next;
                }
                my $expr_sql = $property->expr_sql;
                if (exists $filters{$property_name}) {
                    push @sql_filters, 
                        $table_name => { 
                            # cheap hack of prefixing with a whitespace differentiates 
                            # from a regular column below
                            " " . $expr_sql => { operator => $operator, value_position => $value_position }
                        };
                }
                next;
            }

            if (my $column_name = $property->column_name) {
                # normal column: filter on it
                unless ($table_name) {
                    $ds->warning_message("Property '$property_name' of class '$class_name'  has column '$column_name' but has no table!");
                    next;
                }
                if (exists $filters{$property_name}) {
                    push @sql_filters, 
                        $table_name => { 
                            $column_name => { operator => $operator, value_position => $value_position } 
                        };
                }
            }
            elsif ($property->is_transient) {
                die "Query by transient property $property_name on $class_name cannot be done!";
            }
            elsif ($property->is_delegated) {
                push @delegated_properties, $property->property_name;
            }
            elsif ($property->is_calculated || $property->is_constant) {
                $needs_further_boolexpr_evaluation_after_loading = 1;
            }
            else {
                next;
            }

        } # end of properties in the expression which control the query content 

        if (@errors) { 
            my $class_name = $class_meta->class_name;
            $ds->error_message("Unknown param(s) (" . join(',', map { "'$_'" } @errors) . ") used to generate SQL for $class_name!");
            print Data::Dumper::Dumper($rule_template);
            Carp::confess();
        }
    };
    
    my $object_num = 0; 
    my $alias_num = 0;
    
    my %alias_sql_join;
    my %joins_done;

    # FIXME - this needs to be broken out into delegated-property-join-resolver
    # and inheritance-join-resolver methods that can be called recursively.
    # It would better encapsulate what's going on and avoid bugs with complicated
    # get()s
    
    DELEGATED_PROPERTY:
    for my $delegated_property (@delegated_properties) {
        my $property_name = $delegated_property;
       
        my ($final_accessor, $is_optional, @joins) = _resolve_object_join_data_for_property_chain($rule_template,$property_name);
       
        if ($joins[-1]{foreign_class}->isa("UR::Value")) {
            # the final join in a chain is often the link between a primitive value
            # and the UR::Value subclass into which it falls ...irrelevent for db joins
            pop @joins;
        }

        my $alias_for_property_value;
        my $last_class_object_excluding_inherited_joins;
        my $join_aliases_for_this_object;
        my @source_table_and_column_names;

        my $flattened_value;

        while (my $object_join = shift @joins) { # one iteration per table between the start table and target
            #$DB::single = 1;
            #print "\tjoin $object_join\n";
            #        print Data::Dumper::Dumper($object_join);

            $object_num++;

            my @joins_for_object = ($object_join);

            my $joins_for_object = 0;

            # one iteration per layer of inheritance at this join
            # or per case of a join having additional filtering
            while (my $join = shift @joins_for_object) { 

                my $where = $join->{where};
                if (0) { #($where) {
                    # a where clause might imply additional joins, requiring we pre-empt
                    # continuing through the join chain until these are resolved
                    $DB::single = 1;
                    my $c = $join->{foreign_class};
                    my $m = $c->__meta__;
                    my $bx = UR::BoolExpr->resolve($c,@$where);
                    my %p = $bx->params_list; # FIXME
                    my @p = sort keys %p;
                    my @added_joins;
                    for my $pn (@p) {
                        my $p = $m->property($pn);
                        my @j = $p->_resolve_join_chain();
                        my $j = pop @j;
                        $j = { %$j };
                        my $w = delete $j->{where};

                        if (@j) {
                            unshift @added_joins, @j;
                        }
                    }
                    if (@added_joins) {
                        $DB::single = 1;
                        $join = { %$join };
                        delete $join->{where};
                        push @added_joins, $join;
                        unshift @joins_for_object, @added_joins;
                        next;
                    }
                }
                
                $joins_for_object++;

                my $source_class_name = $join->{source_class};
                my $source_class_object = $join->{'source_class_meta'} || $source_class_name->__meta__;                    

                my $foreign_class_name = $join->{foreign_class};
                my $foreign_class_object = $join->{'foreign_class_meta'} || $foreign_class_name->__meta__;
                my($foreign_data_source) = UR::Context->resolve_data_sources_for_class_meta_and_rule($foreign_class_object, $rule_template);
                if (!$foreign_data_source or ($foreign_data_source ne $ds)) {
                    # FIXME - do something smarter in the future where it can do a join-y thing in memory
                    $needs_further_boolexpr_evaluation_after_loading = 1;
                    next DELEGATED_PROPERTY;
                }

                # This will get filled in during the first pass, and every time after we've successfully
                # performed a join - ie. that the delegated property points directly to a class/property
                # that is a real table/column, and not a tableless class or another delegated property
                unless (@source_table_and_column_names) {
                    my @source_property_names = @{ $join->{source_property_names} };

                    @source_table_and_column_names =
                        map {
                            if ($_->[0] =~ /^(.*)\s+(\w+)\s*$/s) {
                                # This "table_name" was actually a bit of SQL with an inline view and an alias
                                # FIXME - this won't work if they used the optional "as" keyword
                                $_->[0] = $1;
                                $_->[2] = $2;
                            }
                            $_;
                        }
                        map {
                            my $p = $source_class_object->property_meta_for_name($_);
                            unless ($p) {
                                Carp::confess("No property $_ for class ".$source_class_object->class_name);
                            }
                            my($table_name,$column_name) = $p->table_and_column_name_for_property();
                            if ($table_name && $column_name) {
                                [$table_name, $column_name];
                            } else {
                                #Carp::confess("Can't determine table and column for property $_ in class " .
                                #              $source_class_object->class_name);
                                ();
                            }
                        }
                        @source_property_names;
                }

                my @foreign_property_names = @{ $join->{foreign_property_names} };
                my @foreign_property_meta = 
                    map { $foreign_class_object->property_meta_for_name($_) }
                    @foreign_property_names;
                my $foreign_table_name;
                my @foreign_column_names = 
                    map {
                        # TODO: encapsulate
                        if ($_->is_calculated) {
                            if ($_->calculate_sql) {
                                $_->calculate_sql;
                            } else {
                                ();
                            }
                        } else {
                            my $foreign_column_name;
                            ($foreign_table_name, $foreign_column_name) = $_->table_and_column_name_for_property();
                            $foreign_column_name;
                        }
                    }
                    @foreign_property_meta;

                unless (@foreign_column_names) {
                    # all calculated properties: don't try to join any further
                    last;
                }
                unless (@foreign_column_names == @foreign_property_meta) {
                    # some calculated properties, be sure to re-check for a match after loading the object
                    $needs_further_boolexpr_evaluation_after_loading = 1;
                }
                if ($foreign_table_name and $foreign_table_name =~ /^(.*)\s+(\w+)\s*$/s) {
                    $foreign_table_name = $1;
                }

                unless ($foreign_table_name) {
                    # If we can't make the join because there is no datasource representation
                    # for this class, we're done following the joins for this property
                    # and will NOT try to filter on it at the datasource level
                    $needs_further_boolexpr_evaluation_after_loading = 1;
                    next DELEGATED_PROPERTY;
                }

                my $foreign_class_loading_data = $ds->_get_class_data_for_loading($foreign_class_object);

                my $alias = $joins_done{$join->{id}};

                unless ($alias) {
                    $alias_num++;
                    
                    my $alias_length = length($property_name)+length($alias_num)+1;
                    my $alias_max_length = 29;
                    if ($alias_length > $alias_max_length) {
                        $alias = substr($property_name,0,$alias_max_length-length($alias_num)-1); 
                    }
                    else {
                        $alias = $property_name;
                    }
                    $alias =~ s/\./_/g;
                    $alias .= '_' . $alias_num; 

                    if ($foreign_class_object->table_name) {
                        my @extra_filters;

                        # TODO This may not work correctly if the property we're joining on doesn't 
                        # have a table to get data from
                        if ($where) {
                            $DB::single = 1;
                            # temp hack
                            # todo: switch to rule processing
                            for (my $n = 0; $n < @$where; $n += 2) {
                                my $key =$where->[$n];
                                my ($name,$op) = ($key =~ /^(\S+)\s*(.*)/);
                                my $meta = $foreign_class_object->property_meta_for_name($name);
                                unless ($meta) {
                                    print "no meta for $name in " . $foreign_class_object->id; 
                                }
                                my $column = $meta->is_calculated ? (defined($meta->calculate_sql) ? ($meta->calculate_sql) : () ) : ($meta->column_name);
                                my $value = $where->[$n+1];
                                push @extra_filters, $column => { value => $value, ($op ? (operator => $op) : ()) };
                            }
                        }

                        push @sql_joins,
                            "$foreign_table_name $alias" =>
                            {
                                (
                                    map {
                                        $foreign_column_names[$_] => { 
                                            link_table_name     => $join_aliases_for_this_object->{$source_table_and_column_names[$_][0]} # join alias
                                                                   || $source_table_and_column_names[$_][2]  # SQL inline view alias
                                                                   || $source_table_and_column_names[$_][0], # table_name
                                            link_column_name    => $source_table_and_column_names[$_][1] 
                                        }
                                    }
                                    (0..$#foreign_column_names)
                                ),
                                @extra_filters,
                            };
                        $alias_sql_join{$alias} = $sql_joins[-1];

                        # Add all of the columns in the join table to the return list
                        # Note that we increment the object numbers.
                        # Note: we add grouping columns individually instead of in chunks
                        if ($group_by) {
                            #$DB::single = 1;
                        }
                        else {
                            push @all_table_properties,
                                 map {
                                     my $new = [@$_]; 
                                     $new->[2] = $alias;
                                     $new->[3] = $object_num; 
                                     $new 
                                 }
                                 @{ $foreign_class_loading_data->{direct_table_properties} };                
                        }
                    }
                }

                if ($foreign_class_object->table_name) {
                    $join_aliases_for_this_object->{$foreign_table_name} = $alias;
                    @source_table_and_column_names = ();  # Flag that we need to re-derive this at the top of the loop
                }

                if ($group_by) {
                    if ($group_by_property_names{$property_name}) {
                        my ($p) = 
                            map {
                                my $new = [@$_]; 
                                $new->[2] = $alias;
                                $new->[3] = 0; 
                                $new 
                            }
                            grep { $_->[1]->property_name eq $final_accessor }
                            @{ $foreign_class_loading_data->{direct_table_properties} };
                        push @all_table_properties, $p;
                        #print "PROPERTY $property_name IS INVOLVED IN GROUPING: $p\n";
                    }
                    #else {
                    #    $DB::single = 1;
                    #    #print "PROPERTY $property_name IS NOT INVOLVDED IN GROUPING!\n";
                    #}
                }

                if ($order_by) {
                    if ($order_by_property_names{$property_name}) {
                        my ($p) = 
                            map {
                                my $new = [@$_]; 
                                $new->[2] = $alias;
                                $new->[3] = 0; 
                                $new 
                            }
                            grep { $_->[1]->property_name eq $final_accessor }
                            @{ $foreign_class_loading_data->{direct_table_properties} };
                        $order_by_property_names{$property_name} = $p if $p;
                        #print "PROPERTY $property_name IS INVOLVED IN ORDERING: $p\n";
                    }
                    #else {
                    #    $DB::single = 1;
                    #    #print "PROPERTY $property_name IS NOT INVOLVDED IN ORDERING!\n";
                    #}
                    #my @order_table_debug = %order_by_property_names;  
                    #print "  ORDER HAS @order_table_debug\n" if $order_by;
                }

                unless ($is_optional) {
                    # if _any_ part requires this, mark it required
                    $alias_sql_join{$alias}{-is_required} = 1;
                }

                $joins_done{$join->{id}} = $alias;

                # Set these for after all of the joins are done
                my $last_class_name = $foreign_class_name;
                my $last_class_object = $foreign_class_object;

                if ($joins_for_object == 1) {
                    #$last_alias_for_this_delegate = $alias;
                    if ($final_accessor and $last_class_object->property_meta_for_name($final_accessor)) {
                        $last_class_object_excluding_inherited_joins = $last_class_object;
                    }
                    # on the first iteration, we figure out the remaining inherited iterations
                    # TODO: get this into the join logic itds in the property meta
                    my @parents = grep { $_->table_name } $foreign_class_object->ancestry_class_metas;
                    if (@parents) {
                        my @last_id_property_names = $foreign_class_object->id_property_names;
                        for my $parent (@parents) {
                            my @parent_id_property_names = $parent->id_property_names;
                            die if @parent_id_property_names > 1;                    
                            unshift @joins_for_object, {
                                source_class => $last_class_name,
                                source_property_names => [@last_id_property_names], # we change content below
                                foreign_class => $parent->class_name,
                                foreign_property_names => \@parent_id_property_names,
                                is_optional => $is_optional,
                                id => "${last_class_name}::" . join(',',@last_id_property_names),
                            };
                            @last_id_property_names = @parent_id_property_names;
                            $last_class_name = $foreign_class_name;
                        }
                        next;
                    }
                }

                if (!@joins and not $alias_for_property_value) {
                    if ($final_accessor and
                        grep { $_->[1]->property_name eq $final_accessor } @{ $foreign_class_loading_data->{direct_table_properties} }
                    ) {
                        $alias_for_property_value = $alias;
                        #print "found alias for $property_name on $foreign_class_name: $alias\n";
                    }
                    else {
                        # The thing we're joining to isn't a database-backed column (maybe calculated?)
                        $needs_further_boolexpr_evaluation_after_loading = 1;
                        next DELEGATED_PROPERTY;
                    }
                }

            } # next join for this object

        } # next object join

        if (ref($delegated_property) and !$delegated_property->via) {
            next;
        }

        my $final_accessor_property_meta = $last_class_object_excluding_inherited_joins->property_meta_for_name($final_accessor);
        unless ($final_accessor_property_meta) {
            Carp::croak("No property metadata for property named '$final_accessor' in class "
                        . $last_class_object_excluding_inherited_joins->class_name
                        . " while resolving joins for property '" . $delegated_property->property_name . "' in class "
                        . $delegated_property->class_name);
        }

        # we don't know for all of the joined properties how they connect back,
        # but we do know for those which drove the joining
        #for my $pmeta (reverse @all_table_properties) {
        #    if ($pmeta->[1] == $final_accessor_property_meta) {
        #        $pmeta->[4] = $property_name;
        #    }
        #}

        my $sql_lvalue;
        if ($final_accessor_property_meta->is_calculated) {
            $sql_lvalue = $final_accessor_property_meta->calculate_sql;
            unless (defined($sql_lvalue)) {
                $needs_further_boolexpr_evaluation_after_loading = 1;
                next;
            }
        }
        else {
            $sql_lvalue = $final_accessor_property_meta->column_name;
            unless (defined($sql_lvalue)) {
                Carp::confess("No column name set for non-delegated/calculated property $property_name of $class_name");
            }
        }

        my $value_position = $rule_template->value_position_for_property_name($property_name);
        if (defined $value_position) {
            my $operator       = $rule_template->operator_for($property_name);

            unless ($alias_for_property_value) {
                die "No alias found for $property_name?!";
            }

            push @sql_filters, 
                $alias_for_property_value => { 
                    $sql_lvalue => { operator => $operator, value_position => $value_position } 
                };
        }
    } # next delegated property

    # the following two sets of variables hold the net result of the logic
    my $select_clause;
    my $select_hint;
    my $from_clause;
    my $connect_by_clause;
    my $group_by_clause;

    # Build the SELECT clause explicitly.
    $select_clause = $ds->_select_clause_for_table_property_data(@all_table_properties);

    # Oracle places group_by in a comment in the select 
    $select_hint = $class_meta->query_hint;

    # Build the FROM clause base.
    # Add joins to the from clause as necessary, then
    $from_clause = (defined $first_table_name ? "$first_table_name" : '');        

    my $cnt = 0;
    my @sql_params;
    while (@sql_joins) {
        my $table_name = shift (@sql_joins);
        my $condition  = shift (@sql_joins);
        my ($table_alias) = ($table_name =~ /(\S+)\s*$/s);

        my $join_type;
        if ($condition->{-is_required}) {
            $join_type = 'INNER';
        }
        else {
            $join_type = 'LEFT';
        }

        $from_clause .= "\n$join_type join " . $table_name . " on ";
        # Restart the counter on each join for the from clause,
        # but for the where clause keep counting w/o reset.
        $cnt = 0;

        for my $column_name (keys %$condition) {
            next if substr($column_name,0,1) eq '-';

            my $linkage_data = $condition->{$column_name};
            my $expr_sql = (substr($column_name,0,1) eq " " ? $column_name : "${table_alias}.${column_name}");                                
            my @keys = qw/operator value_position value link_table_name link_column_name/;
            my ($operator, $value_position, $value, $link_table_name, $link_column_name) = @$linkage_data{@keys};

            $from_clause .= "\n    and " if ($cnt++);

            if ($link_table_name and $link_column_name) {
                # the linkage data is a join specifier
                $from_clause .= "${link_table_name}.${link_column_name} = $expr_sql";
            }
            elsif (defined $value_position) {
                Carp::croak("Joins cannot use variable values currently!");
            }
            else {
                my ($more_sql, @more_params) = $ds->_extend_sql_for_column_operator_and_value($expr_sql, $operator, $value);   
                if ($more_sql) {
                    $from_clause .= $more_sql;
                    push @sql_params, @more_params;
                }
                else {
                    # error
                    return;
                }
            }
        } # next column                
    } # next join

    # build the WHERE clause by making a data structure which will be parsed outside of this module
    # special handling of different size lists, and NULLs, make a completely reusable SQL template very hard.
    my @filter_specs;         
    while (@sql_filters) {
        my $table_name = shift (@sql_filters);
        my $condition  = shift (@sql_filters);
        my ($table_alias) = ($table_name =~ /(\S+)\s*$/s);

        for my $column_name (keys %$condition) {
            my $linkage_data = $condition->{$column_name};
            my $expr_sql = (substr($column_name,0,1) eq " " ? $column_name : "${table_alias}.${column_name}");                                
            my @keys = qw/operator value_position value link_table_name link_column_name/;
            my ($operator, $value_position, $value, $link_table_name, $link_column_name) = @$linkage_data{@keys};

            if ($link_table_name and $link_column_name) {
                # the linkage data is a join specifier
                Carp::confess("explicit column linkage in where clause?");
                #$sql .= "${link_table_name}.${link_column_name} = $expr_sql";
            }
            else {         
                # the linkage data is a value position from the @values list       
                unless (defined $value_position) {
                    Carp::confess("No value position for $column_name in query!");
                }                
                push @filter_specs, [$expr_sql, $operator, $value_position];
            }
        } # next column                
    } # next join/filter

    $connect_by_clause = ''; 
    if ($recursion_desc) {
        my ($this,$prior) = @{ $recursion_desc };

        my $this_property_meta = $class_meta->property_meta_for_name($this);
        my $prior_property_meta = $class_meta->property_meta_for_name($prior);

        my $this_class_meta = $this_property_meta->class_meta;
        my $prior_class_meta = $prior_property_meta->class_meta;

        my $this_table_name = $this_class_meta->table_name;
        my $prior_table_name = $prior_class_meta->table_name;

        my $this_column_name = $this_property_meta->column_name || $this;
        my $prior_column_name = $prior_property_meta->column_name || $prior;

        $connect_by_clause = "connect by $this_table_name.$this_column_name = prior $prior_table_name.$prior_column_name\n";
        #$DB::single = 1;
    }    

    my @property_names_in_resultset_order;
    for my $property_meta_array (@all_table_properties) {
        push @property_names_in_resultset_order, $property_meta_array->[1]->property_name; 
    }

    # this is only used when making a real instance object instead of a "set"
    my $per_object_in_resultset_loading_detail;
    unless ($group_by) {
        $per_object_in_resultset_loading_detail = $ds->_generate_loading_templates_arrayref(\@all_table_properties);
    }

    if ($group_by) {
        # when grouping, we're making set objects instead of regular objects
        # this means that we re-constitute the select clause and add a group_by clause
        #$DB::single = 1;
        $group_by_clause = 'group by ' . $select_clause if (scalar(@$group_by));

        # FIXME - does it even make sense for the user to specify an order_by in the
        # get() request for Set objects?  If so, then we need to concatonate these order_by_columns
        # with the ones that already exist in $order_by_columns from the class data
        $order_by_columns = $ds->_select_clause_columns_for_table_property_data(@all_table_properties);

        $select_clause .= ', ' if $select_clause;
        $select_clause .= 'count(*) count';

        for my $ag (@$aggregate) {
            next if $ag eq 'count';
             # TODO: translate property names to column names, and skip non-column properties 
            $select_clause .= ', ' . $ag;
        }

        unless (@$group_by == @all_table_properties) {
            print "mismatch table properties vs group by!\n";
        }
    }

    my @order_table_debug = %order_by_property_names;  
    if ($order_by) {
        my @data;
        for my $name (@$order_by) {
            my $data = $order_by_property_names{$name};
            unless (ref($data)) {
                next;
            }
            push @data, $data;
        }
        if (@data) {
            my $additional_order_by_columns = $ds->_select_clause_columns_for_table_property_data(@data);

            # Strip out columns named in the original $order_by_columns list that now appear in the
            # additional order by list so we don't duplicate columns names, and the additional columns
            # appear earlier in the list
            my %additional_order_by_columns = map { $_ => 1 } @$additional_order_by_columns;
            my @existing_order_by_columns = grep { ! $additional_order_by_columns{$_} } @$order_by_columns;
            $order_by_columns = [ @$additional_order_by_columns, @existing_order_by_columns ];
        }
    }
    
    %$self = (
        %$self,

        
        # custom for RDBMS
        select_clause                               => $select_clause,
        select_hint                                 => $select_hint,
        from_clause                                 => $from_clause,        
        connect_by_clause                           => $connect_by_clause,
        group_by_clause                             => $group_by_clause,
        order_by_columns                            => $order_by_columns,        
        filter_specs                                => \@filter_specs,
        sql_params                                  => \@sql_params,

        # override defaults in the regular datasource $parent_template_data
        needs_further_boolexpr_evaluation_after_loading => $needs_further_boolexpr_evaluation_after_loading,
        property_names_in_resultset_order           => \@property_names_in_resultset_order,
        properties_meta_in_resultset_order          => \@all_table_properties,
        loading_templates                           => $per_object_in_resultset_loading_detail,
    );

    my $template_data = $rule_template->{loading_data_cache} = $self; 
    return $self;
}

sub _resolve_db_joins_for_inheritance {
    my $class_meta = $_[0];

    my $first_table_name;
    my @sql_joins;

    my $prev_table_name; 
    my $prev_id_column_name; 

    my @parent_class_objects  = $class_meta->ancestry_class_metas;

    for my $co ( $class_meta, @parent_class_objects ) {
        my $class_name = $co->class_name;
        my @id_property_objects = $co->direct_id_property_metas;
        my %id_properties = map { $_->property_name => 1 } @id_property_objects;
        my @id_column_names =
            map { $_->column_name }
            @id_property_objects;

        my $table_name = $co->table_name;
        if ($table_name) {
            $first_table_name ||= $table_name;
            if ($prev_table_name) {
                die "Database-level inheritance cannot be used with multi-value-id classes ($class_name)!" if @id_property_objects > 1;
                my $prev_table_alias;
                if ($prev_table_name =~ /.*\s+(\w+)\s*$/) {
                    $prev_table_alias = $1;
                }
                else {
                    $prev_table_alias = $prev_table_name;
                }
                push @sql_joins,
                    $table_name =>
                    {
                        $id_property_objects[0]->column_name => { 
                            link_table_name => $prev_table_alias, 
                            link_column_name => $prev_id_column_name 
                        },
                        -is_required => 1,
                    };
            }
            $prev_table_name = $table_name;
            $prev_id_column_name = $id_property_objects[0]->column_name;
        }
    }

    return ($first_table_name, @sql_joins);
}

sub _resolve_object_join_data_for_property_chain {
    my ($rule_template, $property_name) = @_;
    my $class_meta = $rule_template->subject_class_name->__meta__;
    
    my @joins;
    my $is_optional;
    my $final_accessor;

    my @pmeta = $class_meta->property_meta_for_name($property_name);  

    # we can't actually get this from the joins because 
    # a bunch of optional things can be chained together to form
    # something non-optional
    $is_optional = 0;
    for my $pmeta (@pmeta) {
        push @joins, $pmeta->_resolve_join_chain();
        $is_optional = 1 if $pmeta->is_optional or $pmeta->is_many;
    }

    if (0) { #($joins[-1]->{foreign_class}->isa("UR::Value")) {
        my $j = pop @joins;
        return ($j->{source_name_for_foreign}, $is_optional, @joins)
    }
    else {
        return ($joins[-1]->{source_name_for_foreign}, $is_optional, @joins)
    }
};

sub _init_core {
    my $self = shift;
    my $rule_template = $self->rule_template;
    my $ds = $self->data_source;

    # TODO: most of this only applies to the RDBMS subclass,
    # but some applies to any datasource.  It doesn't hurt to have the RDBMS stuff
    # here and ignored, but it's not placed correctly.
        
    # class-based values
    
    my $class_name = $rule_template->subject_class_name;
    my $class_meta = $class_name->__meta__;
    my $class_data = $ds->_get_class_data_for_loading($class_meta);       

    my @parent_class_objects                = @{ $class_data->{parent_class_objects} };
    my @all_properties                      = @{ $class_data->{all_properties} };
#    my $first_table_name                    = $class_data->{first_table_name};
    my $sub_classification_meta_class_name  = $class_data->{sub_classification_meta_class_name};
    my $subclassify_by    = $class_data->{subclassify_by};
    
    my @all_id_property_names               = @{ $class_data->{all_id_property_names} };
    my @id_properties                       = @{ $class_data->{id_properties} };   
    my $id_property_sorter                  = $class_data->{id_property_sorter};    
    
#    my $order_by_clause                     = $class_data->{order_by_clause};
    
#    my @lob_column_names                    = @{ $class_data->{lob_column_names} };
#    my @lob_column_positions                = @{ $class_data->{lob_column_positions} };
    
#    my $query_config                        = $class_data->{query_config}; 
#    my $post_process_results_callback       = $class_data->{post_process_results_callback};

    my $sub_typing_property                 = $class_data->{sub_typing_property};
    my $class_table_name                    = $class_data->{class_table_name};
    #my @type_names_under_class_with_no_table= @{ $class_data->{type_names_under_class_with_no_table} };
    
    # individual query/boolexpr based
    
    my $recursion_desc = $rule_template->recursion_desc;
    my $recurse_property_on_this_row;
    my $recurse_property_referencing_other_rows;
    if ($recursion_desc) {
        ($recurse_property_on_this_row,$recurse_property_referencing_other_rows) = @$recursion_desc;        
    }        
    
    # _usually_ items freshly loaded from the DB don't need to be evaluated through the rule
    # because the SQL gets constructed in such a way that all the items returned would pass anyway.
    # But in certain cases (a delegated property trying to match a non-object value (which is a bug
    # in the caller's code from one point of view) or with calculated non-sql properties, then the
    # sql will return a superset of the items we're actually asking for, and the loader needs to
    # validate them through the rule
    my $needs_further_boolexpr_evaluation_after_loading; 
    
    # Does fulfilling this request involve querying more than one data source?
    my $is_join_across_data_source;

    my @sql_params;
    my @filter_specs;         
    my @property_names_in_resultset_order;
    my $object_num = 0; # 0-based, usually zero unless there are joins
    
    my @filters = $rule_template->_property_names;
    my %filters =     
        map { $_ => 0 }
        grep { substr($_,0,1) ne '-' }
        @filters;
    
    unless (@all_id_property_names == 1 && $all_id_property_names[0] eq "id") {
        delete $filters{'id'};
    }
    
    my (
        @sql_joins,
        @sql_filters, 
        $prev_table_name, 
        $prev_id_column_name, 
        $eav_class, 
        @eav_properties,
        $eav_cnt, 
        %pcnt, 
        $pk_used,
        @delegated_properties,    
        %outer_joins,
        %chain_delegates,
    );

    for my $key (keys %filters) {
        if (index($key,'.') != -1) {
            $chain_delegates{$key} = delete $filters{$key};
        }
    }
    for my $co ( $class_meta, @parent_class_objects ) {
#        my $table_name = $co->table_name;
#        next unless $table_name;

#        $first_table_name ||= $table_name;

        my $type_name  = $co->type_name;
        my $class_name = $co->class_name;
        
        last if ( ($class_name eq 'UR::Object') or (not $class_name->isa("UR::Object")) );
        
        my @id_property_objects = $co->direct_id_property_metas;
        
        if (@id_property_objects == 0) {
            @id_property_objects = $co->property_meta_for_name("id");
            if (@id_property_objects == 0) {
                $DB::single = 1;
                Carp::confess("Couldn't determine ID properties for $class_name\n");
            }
        }
        
        my %id_properties = map { $_->property_name => 1 } @id_property_objects;
        my @id_column_names =
            map { $_->column_name }
            @id_property_objects;
        
#        if ($prev_table_name)
#        {
#            # die "Database-level inheritance cannot be used with multi-value-id classes ($class_name)!" if @id_property_objects > 1;
#            Carp::confess("No table for class $co->{class_name}") unless $table_name; 
#            push @sql_joins,
#                $table_name =>
#                    {
#                        $id_property_objects[0]->column_name => { 
#                            link_table_name => $prev_table_name, 
#                            link_column_name => $prev_id_column_name 
#                        }
#                    };
#            delete $filters{ $id_property_objects[0]->property_name } if $pk_used;
#        }

        for my $property_name (sort keys %filters)
        {                
            my $property = UR::Object::Property->get(type_name => $type_name, property_name => $property_name);                
            next unless $property;
            
            my $operator       = $rule_template->operator_for($property_name);
            my $value_position = $rule_template->value_position_for_property_name($property_name);
            
            delete $filters{$property_name};
            $pk_used = 1 if $id_properties{ $property_name };
            
#            if ($property->can("expr_sql")) {
#                my $expr_sql = $property->expr_sql;
#                push @sql_filters, 
#                    $table_name => 
#                        { 
#                            # cheap hack of putting a whitespace differentiates 
#                            # from a regular column below
#                            " " . $expr_sql => { operator => $operator, value_position => $value_position }
#                        };
#                next;
#            }
            
            if ($property->is_legacy_eav) {
                die "Old GSC EAV can be handled with a via/to/where/is_mutable=1";
            }
            elsif ($property->is_transient) {
                die "Query by transient property $property_name on $class_name cannot be done!";
            }
            elsif ($property->is_delegated) {
                push @delegated_properties, $property;
            }
            elsif ($property->is_calculated) {
                $needs_further_boolexpr_evaluation_after_loading = 1;
            }
            else {
                # normal column: filter on it
                push @sql_filters, 
                    $class_name => 
                        { 
                            $property_name => { operator => $operator, value_position => $value_position }
                        };
            }
        }
        
#        $prev_table_name = $table_name;
        $prev_id_column_name = $id_property_objects[0]->column_name;
        
    } # end of inheritance loop
        
    if ( my @errors = keys(%filters) ) { 
        my $class_name = $class_meta->class_name;
        $ds->error_message('Unknown param(s) (' . join(',',@errors) . ") used to generate SQL for $class_name!");
        Carp::confess();
    }

    my $last_class_name = $class_name;
    my $last_class_object = $class_meta;        
#    my $last_table_alias = $last_class_object->table_name; 
    my $alias_num = 1;

    my %joins_done;
    my @joins_done;
    my $joins_across_data_sources;

    DELEGATED_PROPERTY:
    for my $delegated_property (@delegated_properties) {
        my $last_alias_for_this_chain;
    
        my $property_name = $delegated_property->property_name;
        my @joins = $delegated_property->_resolve_join_chain;
        #pop @joins if $joins[-1]->{foreign_class}->isa("UR::Value");
        my $relationship_name = $delegated_property->via;
        unless ($relationship_name) {
           $relationship_name = $property_name;
           $needs_further_boolexpr_evaluation_after_loading = 1;
        }

        my $delegate_class_meta = $delegated_property->class_meta;
        my $via_accessor_meta = $delegate_class_meta->property_meta_for_name($relationship_name);
        my $final_accessor = $delegated_property->to;            
        my $final_accessor_meta = $via_accessor_meta->data_type->__meta__->property_meta_for_name($final_accessor);
        unless ($final_accessor_meta) {
            Carp::croak("No property '$final_accessor' on class " . $via_accessor_meta->data_type .
                          " while resolving property $property_name on class $class_name");
        }
        while($final_accessor_meta->is_delegated) {
            $final_accessor_meta = $final_accessor_meta->to_property_meta();
            unless ($final_accessor_meta) {
                Carp::croak("No property '$final_accessor' on class " . $via_accessor_meta->data_type .
                              " while resolving property $property_name on class $class_name");
            }
        }
        $final_accessor = $final_accessor_meta->property_name;

        #print "$property_name needs join "
        #    . " via $relationship_name "
        #    . " to $final_accessor"
        #    . " using joins ";
        
        #my $final_table_name_with_alias = $first_table_name; 
        
        for my $join (@joins) {
            #print "\tjoin $join\n";

            my $source_class_name = $join->{source_class};
            my $source_class_object = $join->{'source_class_meta'} || $source_class_name->__meta__;

            my $foreign_class_name = $join->{foreign_class};
            my $foreign_class_object = $join->{'foreign_class_meta'} || $foreign_class_name->__meta__;
            my($foreign_data_source) = $UR::Context::current->resolve_data_sources_for_class_meta_and_rule($foreign_class_object, $rule_template);
            if (! $foreign_data_source) {
                $needs_further_boolexpr_evaluation_after_loading = 1;
                next DELEGATED_PROPERTY;

            } elsif ($foreign_data_source ne $ds or
                    ! $ds->does_support_joins or
                    ! $foreign_data_source->does_support_joins
                )
            {
                push(@{$joins_across_data_sources->{$foreign_data_source->id}}, $delegated_property);
                next DELEGATED_PROPERTY;
            }

            my @source_property_names = @{ $join->{source_property_names} };

            my @source_table_and_column_names = 
                map {
                    my $p = $source_class_object->property_meta_for_name($_);
                    unless ($p) {
                        Carp::confess("No property $_ for class $source_class_object->{class_name}\n");
                    }
                    [$p->class_name->__meta__->class_name, $p->property_name];
                }
                @source_property_names;

            #print "source column names are @source_table_and_column_names for $property_name\n";            

            my $foreign_table_name = $foreign_class_name;

            unless ($foreign_table_name) {
                # If we can't make the join because there is no datasource representation
                # for this class, we're done following the joins for this property
                # and will NOT try to filter on it at the datasource level
                $needs_further_boolexpr_evaluation_after_loading = 1;
                next DELEGATED_PROPERTY;
            }

            my @foreign_property_names = @{ $join->{foreign_property_names} };
            my @foreign_property_meta = 
                map {
                    $foreign_class_object->property_meta_for_name($_)
                }
                @foreign_property_names;
            
            my @foreign_column_names = 
                map {
                    # TODO: encapsulate
                    $_->is_calculated ? (defined($_->calculate_sql) ? ($_->calculate_sql) : () ) : ($_->property_name)
                }
                @foreign_property_meta;
                
            unless (@foreign_column_names) {
                # all calculated properties: don't try to join any further
                last;
            }
            unless (@foreign_column_names == @foreign_property_meta) {
                # some calculated properties, be sure to re-check for a match after loading the object
                $needs_further_boolexpr_evaluation_after_loading = 1;
            }
            
            my $alias = $joins_done{$join->{id}};
            unless ($alias) {            
                $alias = "${relationship_name}_${alias_num}";
                $alias_num++;
                $object_num++;
                
                push @sql_joins,
                    "$foreign_table_name $alias" =>
                        {
                            map {
                                $foreign_property_names[$_] => { 
                                    link_table_name     => $last_alias_for_this_chain || $source_table_and_column_names[$_][0],
                                    link_column_name    => $source_table_and_column_names[$_][1] 
                                }
                            }
                            (0..$#foreign_property_names)
                        };
                    
                # Add all of the columns in the join table to the return list.                
                push @all_properties, 
                    map { [$foreign_class_object, $_, $alias, $object_num] }
                    sort { $a->property_name cmp $b->property_name }
                    grep { defined($_->column_name) && $_->column_name ne '' }
                    UR::Object::Property->get( type_name => $foreign_class_object->type_name );
              
                $joins_done{$join->{id}} = $alias;
                push @joins_done, $join;
                
            }
            
            # Set these for after all of the joins are done
            $last_class_name = $foreign_class_name;
            $last_class_object = $foreign_class_object;
            $last_alias_for_this_chain = $alias;
            #$last_table_alias = $alias;
            #$final_table_name_with_alias = "$foreign_table_name $alias";
            
        } # next join

        unless ($delegated_property->via) {
            next;
        }

        my $final_accessor_property_meta = $last_class_object->property_meta_for_name($final_accessor);
        if ($final_accessor_property_meta
            and $final_accessor_property_meta->class_name eq 'UR::Object'
            and $final_accessor_property_meta->property_name eq 'id')
        {
            # This is the 'fake' id property.  Remap it to the class' real ID property name
            my @id_properties = $last_class_object->id_property_names;
            if (@id_properties != 1) {
                # TODO - we could add further joins and not have to evaluate later
                $needs_further_boolexpr_evaluation_after_loading = 1;
                next;

            } else {
                $final_accessor_property_meta = $last_class_object->property_meta_for_name($id_properties[0]);
            }
            
        }

        unless ($final_accessor_property_meta) {
            Carp::croak("No property metadata for property named '$final_accessor' in class " . $last_class_object->class_name
                        . " while resolving joins for property '" .$delegated_property->property_name . "' in class "
                        . $delegated_property->class_name);
        }
       
        my $sql_lvalue;
        if ($final_accessor_property_meta->is_calculated) {
            $sql_lvalue = $final_accessor_property_meta->calculate_sql;
            unless (defined($sql_lvalue)) {
                $needs_further_boolexpr_evaluation_after_loading = 1;
                next;
            }
        }
        else {
            $sql_lvalue = $final_accessor_property_meta->column_name;
            unless (defined($sql_lvalue)) {
                Carp::confess("No column name set for non-delegated/calculated property $property_name of $class_name");
            }
        }

        my $operator       = $rule_template->operator_for($property_name);
        my $value_position = $rule_template->value_position_for_property_name($property_name);                
        #push @sql_filters, 
        #    $final_table_name_with_alias => { 
        #        $sql_lvalue => { operator => $operator, value_position => $value_position } 
        #    };
    } # next delegated property
    
    for my $property_meta_array (@all_properties) {
        push @property_names_in_resultset_order, $property_meta_array->[1]->property_name; 
    }
    
    my $rule_template_without_recursion_desc = ($recursion_desc ? $rule_template->remove_filter('-recurse') : $rule_template);
    
    my $rule_template_specifies_value_for_subtype;
    if ($sub_typing_property) {
        $rule_template_specifies_value_for_subtype = $rule_template->specifies_value_for($sub_typing_property)
    }

    my $per_object_in_resultset_loading_detail = $ds->_generate_loading_templates_arrayref(\@all_properties);

    
    %$self = (
        %$self,

        %$class_data,
        
        properties_for_params                       => \@all_properties,  
        property_names_in_resultset_order           => \@property_names_in_resultset_order,
        joins                                       => \@sql_joins,
        
        rule_template_id                            => $rule_template->id,
        rule_template_without_recursion_desc        => $rule_template_without_recursion_desc,
        rule_template_id_without_recursion_desc     => $rule_template_without_recursion_desc->id,
        rule_matches_all                            => $rule_template->matches_all,
        rule_specifies_id                           => ($rule_template->specifies_value_for('id') || undef),
        rule_template_is_id_only                    => $rule_template->is_id_only,
        rule_template_specifies_value_for_subtype   => $rule_template_specifies_value_for_subtype,
        
        recursion_desc                              => $rule_template->recursion_desc,
        recurse_property_on_this_row                => $recurse_property_on_this_row,
        recurse_property_referencing_other_rows     => $recurse_property_referencing_other_rows,
        
        loading_templates                           => $per_object_in_resultset_loading_detail,

        joins_across_data_sources                   => $joins_across_data_sources,
    );
        
    return $self;
}

sub _init_default {
    my $self = shift;
    my $bx_template = $self->rule_template;
    $self->{needs_further_boolexpr_evaluation_after_loading} = 1;
    my $all_possible_headers = $self->{loading_templates}[0]{property_names};
    my $expected_headers;
    my $class_meta = $bx_template->subject_class_name->__meta__;
    for my $pname (@$all_possible_headers) {
        my $pmeta = $class_meta->property($pname);
        if ($pmeta->is_delegated) {
            next;
        }
        push @$expected_headers, $pname;
    }
    $self->{loading_templates}[0]{property_names} = $expected_headers;

    return $self;
}

sub _init_remote_cache {
    my $self = shift;
    my $rule_template = $self->rule_template;
    my $ds = $self->data_source;

    my $class_name = $rule_template->subject_class_name;
    my $class_meta = $class_name->__meta__;
    my $class_data = $ds->_get_class_data_for_loading($class_meta);

    my $recursion_desc = $rule_template->recursion_desc;
    my $rule_template_without_recursion_desc = ($recursion_desc ? $rule_template->remove_filter('-recurse') : $rule_template);
    my $rule_template_specifies_value_for_subtype;
    my $sub_typing_property = $class_data->{'sub_typing_property'};
    if ($sub_typing_property) {
        $rule_template_specifies_value_for_subtype = $rule_template->specifies_value_for($sub_typing_property)
    }

    my @property_names = $class_name->__meta__->all_property_names;

    %$self = (
        %$self,

        select_clause                               => '',
        select_hint                                 => undef,
        from_clause                                 => '',
        where_clause                                => '',
        connect_by_clause                           => '',
        order_by_clause                             => '',

        needs_further_boolexpr_evaluation_after_loading => undef,
        loading_templates                           => [],

        sql_params                                  => [],
        filter_specs                                => [],
        property_names_in_resultset_order           => \@property_names,
        properties_for_params                       => [],

        rule_template_id                            => $rule_template->id,
        rule_template_without_recursion_desc        => $rule_template_without_recursion_desc,
        rule_template_id_without_recursion_desc     => $rule_template_without_recursion_desc->id,
        rule_matches_all                            => $rule_template->matches_all,
        rule_specifies_id                           => ($rule_template->specifies_value_for('id') || undef),
        rule_template_is_id_only                    => $rule_template->is_id_only,
        rule_template_specifies_value_for_subtype   => $rule_template_specifies_value_for_subtype,

        recursion_desc                              => undef,
        recurse_property_on_this_row                => undef,
        recurse_property_referencing_other_rows     => undef,

        %$class_data,
    );

    return $self;
}

1;

