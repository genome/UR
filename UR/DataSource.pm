package UR::DataSource;
use strict;
use warnings;

require UR;
use Sys::Hostname;

*namespace = \&get_namespace;
UR::Object::Type->define(
    class_name => 'UR::DataSource',
    #is => ['UR::Singleton'],
    english_name => 'universal reflective datasource',
    is_abstract => 1,
    doc => 'A logical database, independent of prod/dev/testing considerations or login details.',
    has => [
        namespace => { calculate_from => ['id'] },
    ],
);

sub get_namespace {
    my $class = shift->_singleton_class_name;
    return substr($class,0,index($class,"::DataSource"));
}

sub get_name {
    my $class = shift->_singleton_class_name;
    return lc(substr($class,index($class,"::DataSource")+14));
}

our $use_dummy_autogenerated_ids = ($ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} ||= 0);
sub use_dummy_autogenerated_ids
{
    # This allows the saved SQL from sync database to be comparable across executions.
    # It also 
    my $class = shift;
    if (@_) {
        ($use_dummy_autogenerated_ids) = @_;
        ($ENV{UR_USE_DUMMY_AUTOGENERATED_IDS}) = @_;
    }
    return $use_dummy_autogenerated_ids;
}

our $last_dummy_autogenerated_id;
sub next_dummy_autogenerated_id 
{   
    unless($last_dummy_autogenerated_id) {
        my $hostname = hostname();
        $hostname =~ /(\d+)/;
        my $id = $1 ? $1 : 1;
        $last_dummy_autogenerated_id = $1 * -10000;
    }
    return --$last_dummy_autogenerated_id;
}

sub _get_class_data_for_loading {
    my ($self, $class_meta) = @_;
    my $class_data = $class_meta->{loading_data_cache};

    unless ($class_data) {
        my $class_name = $class_meta->class_name;        
        my $ghost_class = $class_name->ghost_class;
    
        my @all_id_property_names = $class_meta->all_id_property_names();
        my @id_properties = $class_meta->id_property_names;    
        my $id_property_sorter = $class_meta->id_property_sorter;    
    
        my $order_by_clause;
        do {            
            my @id_column_names;    
            for my $inheritance_class_name (
                $class_meta->class_name, 
                $class_meta->ordered_inherited_class_names
            ) {
                my $inheritance_class_object = UR::Object::Type->get($inheritance_class_name);
                unless ($inheritance_class_object->table_name) {
                    next;
                }
                @id_column_names = 
                    map { $inheritance_class_object->table_name . '.' . $_ }
                    grep { defined }
                    map { 
                        $inheritance_class_object->get_property_object(property_name => $_)->column_name 
                    } 
                    $inheritance_class_object->id_property_names;
                    
                last if (@id_column_names);
            }
            $order_by_clause = "order by " . join(",", @id_column_names);
        };
        
        my @parent_class_objects = $class_meta->get_inherited_class_objects;
        my @all_table_properties;
        my $first_table_name;
        my $sub_classification_method_name = $class_meta->sub_classification_method_name;
        my ($sub_classification_meta_class_name, $sub_classification_property_name);
        
        for my $co ( $class_meta, @parent_class_objects )
        {   
            my $table_name = $co->table_name;
            next unless $table_name;
            
            $first_table_name ||= $co->table_name;
            $sub_classification_meta_class_name ||= $co->sub_classification_meta_class_name;
            $sub_classification_property_name   ||= $co->sub_classification_property_name;
            
            push @all_table_properties, 
                map { [$co, $_, $table_name] }
                sort { $a->property_name cmp $b->property_name }
                grep { defined $_->column_name && $_->column_name ne '' }
                UR::Object::Property->get( type_name => $co->type_name );
        }
    
        my @lob_column_names;
        my @lob_column_positions;
        my $pos = 0;
        for my $class_property (@all_table_properties) {
            my ($sql_class,$sql_property,$sql_table_name) = @$class_property;
            my $data_type = $sql_property->data_type || '';             
            if ($data_type =~ /LOB$/) {
                push @lob_column_names, $sql_property->column_name;
                push @lob_column_positions, $pos;
            }
            $pos++;
        }
        
        my $query_config; 
        my $post_process_results_callback;
        if (@lob_column_names) {
            $query_config = $self->_prepare_for_lob;
            if ($query_config) {
                my $dbh = $self->get_default_dbh;
                my $results_row_arrayref;
                my @lob_ids;
                my @lob_values;
                $post_process_results_callback = sub { 
                    $results_row_arrayref = shift;
                    @lob_ids = @$results_row_arrayref[@lob_column_positions];
                    @lob_values = $self->_post_process_lob_values($dbh,\@lob_ids);
                    @$results_row_arrayref[@lob_column_positions] = @lob_values;
                    $results_row_arrayref;
                };
            }
        }
    
        my $sub_typing_property = $class_meta->sub_classification_property_name;
    
        my $class_table_name = $class_meta->table_name;
        my @type_names_under_class_with_no_table;
        unless($class_table_name) {
            my @type_names_under_class_with_no_table = ($class_meta->type_name, $class_meta->all_derived_type_names);
        }

        $class_data = {
            class_name                          => $class_name,
            ghost_class                         => $class_name->ghost_class,
            
            parent_class_objects                => [$class_meta->get_inherited_class_objects], ##
            all_table_properties                => \@all_table_properties,
            first_table_name                    => $first_table_name,
            sub_classification_method_name      => $class_meta->sub_classification_method_name,
            sub_classification_meta_class_name  => $sub_classification_meta_class_name,
            sub_classification_property_name    => $sub_classification_property_name,
            
            all_id_property_names               => [$class_meta->all_id_property_names()],
            id_properties                       => [$class_meta->id_property_names],    
            id_property_sorter                  => $class_meta->id_property_sorter,    
            
            order_by_clause                     => $order_by_clause,
            
            lob_column_names                    => \@lob_column_names,
            lob_column_positions                => \@lob_column_positions,
            
            query_config                        => $query_config, 
            post_process_results_callback       => $post_process_results_callback,
            
            sub_typing_property                 => $sub_typing_property,
            type_names_under_class_with_no_table => \@type_names_under_class_with_no_table,
            class_table_name                    => $class_table_name,            
        };
    };

    return $class_data;
}

sub _get_template_data_for_loading {
    my ($self, $rule_template) = @_;
    my $template_data = $rule_template->{loading_data_cache};
    
    unless ($template_data) {
        my $class_name = $rule_template->subject_class_name;
        my $class_meta = $class_name->get_class_object;
        my $class_data = $self->_get_class_data_for_loading($class_meta);       

        my @parent_class_objects                = @{ $class_data->{parent_class_objects} };
        my @all_table_properties                = @{ $class_data->{all_table_properties} };
        my $first_table_name                    = $class_data->{first_table_name};
        my $sub_classification_meta_class_name  = $class_data->{sub_classification_meta_class_name};
        my $sub_classification_property_name    = $class_data->{sub_classification_property_name};
        
        my @all_id_property_names               = @{ $class_data->{all_id_property_names} };
        my @id_properties                       = @{ $class_data->{id_properties} };   
        my $id_property_sorter                  = $class_data->{id_property_sorter};    
        
        my $order_by_clause                     = $class_data->{order_by_clause};
        
        my @lob_column_names                    = @{ $class_data->{lob_column_names} };
        my @lob_column_positions                = @{ $class_data->{lob_column_positions} };
        
        my $query_config                        = $class_data->{query_config}; 
        my $post_process_results_callback       = $class_data->{post_process_results_callback};

        my $sub_typing_property                 = $class_data->{sub_typing_property};
        my $class_table_name                    = $class_data->{class_table_name};
        my @type_names_under_class_with_no_table= @{ $class_data->{type_names_under_class_with_no_table} };
        
        my $recursion_desc = $rule_template->recursion_desc;
        my $recurse_property_on_this_row;
        my $recurse_property_referencing_other_rows;
        if ($recursion_desc) {
            ($recurse_property_on_this_row,$recurse_property_referencing_other_rows) = @$recursion_desc;        
        }        
        
        # this do{} block is the old sql resolver
        # we do scoping around it to avoid having too much data on the pad of the closure below        
        
        # the following two sets of variables hold the net result of the logic
        
        my $select_clause;
        my $select_hint;
        my $from_clause;
        my $where_clause; # not currently used, since we build that on a per-value-set basis (because of nulls, in())
        my $connect_by_clause;
        #my $order_by_clause  ...is above with the class data

        # _usually_ items freshly loaded from the DB don't need to be evaluated through the rule
        # because the SQL gets constructed in such a way that all the items returned would pass anyway.
        # But in certain cases (a delegated property trying to match a non-object value (which is a bug
        # in the caller's code from one point of view) or with calculated non-sql properties, then the
        # sql will return a superset of the items we're actually asking for, and the loader needs to
        # validate them through the rule
        my $needs_further_boolexpr_evaluation_after_loading; 
        
        my @sql_params;
        my @filter_specs;         
        my @property_names_in_resultset_order;
        my $object_num = 0; # 0-based, usually zero unless there are joins

        do {
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
                $first_table_name,
                
            );

            for my $co ( $class_meta, @parent_class_objects )
            {   
                my $table_name = $co->table_name;
                next unless $table_name;

                $first_table_name ||= $table_name;                

                my $type_name  = $co->type_name;
                my $class_name = $co->class_name;
                
                my @id_property_objects = $co->get_id_property_objects;
                my %id_properties = map { $_->property_name => 1 } @id_property_objects;
                my @id_column_names =
                    map { $_->column_name }
                    @id_property_objects;
                
                # cvsj pushes table properties here

                if ($prev_table_name)
                {
                    die "Database-level inheritance cannot be used with multi-value-id classes ($class_name)!" if @id_property_objects > 1;
                    
                    push @sql_joins,
                        $table_name =>
                            {
                                $id_property_objects[0]->column_name => { 
                                    link_table_name => $prev_table_name, 
                                    link_column_name => $prev_id_column_name 
                                }
                            };
                    delete $filters{ $id_property_objects[0]->property_name } if $pk_used;
                }
                # cvsj makes an array of eav props (empty)                

                for my $property_name (sort keys %filters)
                {                
                    my $property = UR::Object::Property->get(type_name => $type_name, property_name => $property_name);                
                    next unless $property;
                    
                    my $operator       = $rule_template->operator_for_property_name($property_name);
                    my $value_position = $rule_template->value_position_for_property_name($property_name);
                    
                    delete $filters{$property_name};
                    $pk_used = 1 if $id_properties{ $property_name };
                    
                    if ($property->can("expr_sql")) {
                        my $expr_sql = $property->expr_sql;
                        push @sql_filters, 
                            $table_name => 
                                { 
                                    # cheap hack of putting a whitespace differentiates 
                                    # from a regular column below
                                    " " . $expr_sql => { operator => $operator, value_position => $value_position }
                                };
                        next;
                    }
                    
                    if (my $column_name = $property->column_name) {
                        # normal column: filter on it
                        push @sql_filters, 
                            $table_name => 
                                { 
                                    $column_name => { operator => $operator, value_position => $value_position }
                                };
                    }                        
                    elsif ($property->is_legacy_eav) {
                        # no column, join to entity_attribute_value
                        die "Key/value properties ($property_name) cannot be used with multi-value-id classes ($class_name)!" if @id_property_objects > 1;
                        
                        my $attribute_name = $property->attribute_name;                    
                        my $pcnt = $pcnt{$property_name};
                        $pcnt ||= '';
                        $pcnt{$property_name}++;
                        my $alias = "ea_${property_name}${pcnt}";
                        
                        push @sql_joins,
                            "ENTITY_ATTRIBUTE_VALUE $alias" =>
                                {
                                    "TYPE_NAME"      => { operator => '=', value => $type_name },
                                    "ATTRIBUTE_NAME" => { operator => '=', value => $attribute_name },
                                    "ENTITY_ID"      => { link_table_name => $table_name, link_column_name => $id_column_names[0] }
                                };
                        
                        push @sql_filters,
                            "ENTITY_ATTRIBUTE_VALUE $alias" =>
                                {
                                    "VALUE"          => { operator => $operator, value_position => $value_position },
                                };
                        
                        unless ($eav_class) {
                            # do this just once per function call
                            $eav_class = UR::Object::Type->get(class_name => 'GSC::EntityAttributeValue');
                            @eav_properties = 
                                map { [$eav_class, $_, $alias, $object_num] }
                                sort { $a->property_name cmp $b->property_name }
                                grep { defined($_->column_name) } 
                                UR::Object::Property->get(type_name => 'entity attribute value');
                        }
                        $object_num++;
                        push @all_table_properties, map { [$_->[0], $_->[1], $alias, $object_num ] } @eav_properties;
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
                        die "Query by $property_name is unsupported!";
                    }
                }
                
                $prev_table_name = $table_name;
                $prev_id_column_name = $id_property_objects[0]->column_name;
                
            } # end of inheritance loop
                
            if ( my @errors = keys(%filters) ) { 
                my $class_name = $class_meta->class_name;
                $self->error_message("Unknown param(s) >@errors< used to generate SQL for $class_name!");
                Carp::confess();
            }

            my $last_class_name = $class_name;
            my $last_class_object = $class_meta;        
            my $last_table_alias = $last_class_object->table_name; 
            my $alias_num = 1;

            my %joins_done;

$DB::single=1;
            DELEGATED_PROPERTY:
            for my $delegated_property (@delegated_properties) {
                my $last_alias_for_this_chain;
            
                my $property_name = $delegated_property->property_name;
                my $final_accessor = $delegated_property->to;            
                my @joins = $delegated_property->_get_joins;
                my $relationship_name = $delegated_property->via;
                unless ($relationship_name) {
                   $relationship_name = $property_name;
                   $needs_further_boolexpr_evaluation_after_loading = 1;
                }

                #print "$property_name needs join "
                #    . " via $relationship_name "
                #    . " to $final_accessor"
                #    . " using joins ";
                
                my $final_table_name_with_alias = $first_table_name; 
                
                for my $join (@joins) {
                    $DB::single = 1;
                    #print "\tjoin $join\n";

                    my $source_class_name = $join->{source_class};
                    my $source_class_object = $source_class_name->get_class_object;                    

                    my @source_property_names = @{ $join->{source_property_names} };
                    #print "\tlast props @source_property_names\n";

                    my @source_table_and_column_names = 
                        map {
                            my $p = $source_class_object->get_property_meta_by_name($_);
                            if ($p) {
                                #print "column $_ for class $source_class_object->{class_name}\n";
                            }
                            else {
                                Carp::confess("No column $_ for class $source_class_object->{class_name}\n");
                            }
                            [$p->class_name->get_class_object->table_name, $p->column_name];
                        }
                        @source_property_names;

                    #print "source column names are @source_table_and_column_names for $property_name\n";            
        
                    my $foreign_class_name = $join->{foreign_class};
                    my $foreign_class_object = UR::Object::Type->get(class_name => $foreign_class_name);
                    my $foreign_table_name = $foreign_class_object->table_name; # TODO: switch to "base 'from' expr"

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
                            $foreign_class_object->get_property_meta_by_name($_)
                        }
                        @foreign_property_names;
                    my @foreign_column_names = 
                        map {
                            # TODO: encapsulate
                            $_->is_calculated ? (defined($_->calc_sql) ? ($_->calc_sql) : () ) : ($_->column_name)
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
                        push @all_table_properties, 
                            map { [$foreign_class_object, $_, $alias, $object_num] }
                            sort { $a->property_name cmp $b->property_name }
                            grep { defined($_->column_name) && $_->column_name ne '' }
                            UR::Object::Property->get( type_name => $foreign_class_object->type_name );
                      
                        $joins_done{$join->{id}} = $alias;
                        $last_alias_for_this_chain = $alias;
                    }
                    
		    # Set these for after all of the joins are done
                    $last_class_name = $foreign_class_name;
                    $last_class_object = $foreign_class_object;        
                    $last_table_alias = $alias;
                    $final_table_name_with_alias = "$foreign_table_name $alias";
                    
                } # next join

                unless ($delegated_property->via) {
                    next;
                }

                my $final_accessor_property_meta = $last_class_object->get_property_meta_by_name($final_accessor);
                my $sql_lvalue;
                if ($final_accessor_property_meta->is_calculated) {
                    $sql_lvalue = $final_accessor_property_meta->calc_sql;
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

                my $operator       = $rule_template->operator_for_property_name($property_name);
                my $value_position = $rule_template->value_position_for_property_name($property_name);                
                push @sql_filters, 
                    $final_table_name_with_alias => { 
                        $sql_lvalue => { operator => $operator, value_position => $value_position } 
                    };

            } # next delegated property
            
            # Build the SELECT clause explicitly.
           
            $select_clause = '';
            for my $class_property (@all_table_properties) {
                my ($sql_class,$sql_property,$sql_table_name) = @$class_property;
                $sql_table_name ||= $sql_class->table_name;
                $select_clause .= ($class_property == $all_table_properties[0] ? "" : ", ");
                $select_clause .= $sql_table_name . "." . $sql_property->column_name;
            }
           
            # Oracle places hints in a comment in the select 
            $select_hint = $class_meta->query_hint;
            
            # Build the FROM clause base.
            # Add joins to the from clause as necessary, then
            $from_clause = (defined $first_table_name ? "$first_table_name" : '');        
            my $cnt = 0;
            while (@sql_joins) {
                my $table_name = shift (@sql_joins);
                my $condition  = shift (@sql_joins);
                my ($table_alias) = ($table_name =~ /(\S+)\s*$/);
                
                $from_clause .= "\njoin " . $table_name . " on ";
                # Restart the counter on each join for the from clause,
                # but for the where clause keep counting w/o reset.
                $cnt = 0;
                
                for my $column_name (keys %$condition) {
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
                        die "Joins cannot use variable values currently!"
                    }
                    else {
                        my ($more_sql, @more_params) = 
                            $self->_extend_sql_for_column_operator_and_value($expr_sql, $operator, $value);   
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
            $where_clause = ''; # stays empty
            while (@sql_filters)
            {
                my $table_name = shift (@sql_filters);
                my $condition  = shift (@sql_filters);
                my ($table_alias) = ($table_name =~ /(\S+)\s*$/);
                
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
                $connect_by_clause = "connect by $this = prior $prior\n";
            }    
            
            for my $property_meta_array (@all_table_properties) {
                push @property_names_in_resultset_order, $property_meta_array->[1]->property_name; 
            }
        };
        
        my $rule_template_without_recursion_desc = ($recursion_desc ? $rule_template->remove_filter('-recurse') : $rule_template);
        
        my $rule_template_specifies_value_for_subtype;
        if ($sub_typing_property) {
            $rule_template_specifies_value_for_subtype = $rule_template->specifies_value_for_property_name($sub_typing_property)
        }

        $template_data = $rule_template->{loading_data_cache} = {
            select_clause                               => $select_clause,
            select_hint                                 => $select_hint,
            from_clause                                 => $from_clause,
            where_clause                                => $where_clause,
            connect_by_clause                           => $connect_by_clause,
            order_by_clause                             => $order_by_clause,

            needs_further_boolexpr_evaluation_after_loading => $needs_further_boolexpr_evaluation_after_loading,
            
            sql_params                                  => \@sql_params,
            filter_specs                                => \@filter_specs,
            property_names_in_resultset_order           => \@property_names_in_resultset_order,
            properties_for_params                       => \@all_table_properties,  # this is a modified version of the one in the class data, extended by joins, etc.
                                                                                    # the former exists under its original name below
            
            rule_template_id                            => $rule_template->id,
            rule_template_without_recursion_desc        => $rule_template_without_recursion_desc,
            rule_template_id_without_recursion_desc     => $rule_template_without_recursion_desc->id,
            rule_matches_all                            => $rule_template->matches_all,
            rule_specifies_id                           => ($rule_template->specifies_value_for_property_name('id') || undef),
            rule_template_is_id_only                    => $rule_template->is_id_only,
            rule_template_specifies_value_for_subtype   => $rule_template_specifies_value_for_subtype,
            
            recursion_desc                              => $rule_template->recursion_desc,
            recurse_property_on_this_row                => $recurse_property_on_this_row,
            recurse_property_referencing_other_rows     => $recurse_property_referencing_other_rows,
                        
            %$class_data,
        };

        if ($object_num > 0) {
            #print "override loading templates!\n";
            $template_data->{loading_templates}
                = $self->_generate_loading_templates_arrayref(\@all_table_properties);
        }

    } # done generating $data hashref on first call
    
    return $template_data;
}
1;
#$Header
