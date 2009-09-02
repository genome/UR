
package UR::Object::Set;

use strict;
use warnings;

use Data::Dumper;
use UR;

require GSCFind;
our %names = (
    'GSC::Project'            => "projects",
    'GSC::Sequence::Read'     => "reads",
);

sub _get_legacy_gscfind_spec {
    my $self = shift;
    my $member_class_name = $self->member_class_name;
    
    my $spec_name = $names{$member_class_name};    
    my $spec = $GSCFind::config{$spec_name};
    unless ($spec) {
        die "Unknown type '$spec_name'.\n"; #  Try \"gscfind --list-types.\"\n";
    }    
    
    return $spec;
}

############

UR::Object::Type->define(
    class_name => 'UR::Object::Set',    
    is => 'UR::Value',
    is_abstract => 1,
    doc => 'an ordered group of distinct UR::Objects',    
    sub_classification_method_name => '_sub_classify',
    has => [
        rule                => { is => 'UR::BoolExpr', id_by => 'id' },
        rule_template       => { via => 'rule' },
        member_class_name   => { via => 'rule', to => 'subject_class_name' },
    ],
);

our $REC;
sub _recursive (&) {
    my ($code) = @_;
    $DB::single = 1;
    my $rec = do { no strict 'refs'; \*{caller() . '::REC'} };
    return sub {
        local *$rec = \$code;
        &$code;
    };
}

sub _sub_classify {
    my $self = shift;
    my $member_class_name = $self->member_class_name;
    return $member_class_name . '::NewSet';
}

sub _generate_class_for_member_class_name {
    my $class = shift;
    
    my $member_class_name = shift;    
    my $set_class_name = $member_class_name . "::Set";
    
    my $class_obj = UR::Object::Type->define(  
        class_name => ,
        is => __PACKAGE__
    );
    
    # generate set accessors
    
    my $spec_name = $names{$member_class_name};
    my $spec;
    if ($spec_name) {
        $spec = $GSCFind::config{$spec_name};
    }
    
    my %alias_property_names;
    if ($spec) {
        %alias_property_names =
            map { $_ => 1 }
            (
                $member_class_name->property_names,
                ($spec_name ? keys %{ $spec->{aliases} } : () )
            );
    }
    else {
        my $meta = $member_class_name->get_class_object;
        $spec = {
            data_source => $meta->data_source,
            table_name => $meta->table_name,
            developer_only => 1,
            default_show => [ $meta->_all_property_names ],
            aliases => {},
            relationships => {},
            #from_clause => 
        };
        # DRY
        $spec_name = $member_class_name;
        $GSCFind::config{$spec_name} = $spec;
        $GSCFind::config{$member_class_name} = $spec_name;
        %alias_property_names = map { $_ => 1 } keys %{ $spec->{aliases} };
    }
    
    for my $property (sort keys %alias_property_names) {
        my $accessor = sub {
            if (@_ > 1) {
                die "accessor $property is not read-write";
            }
            if (exists $_[0]->{$property}) {
                return $_[0]->{$property};
            }
            else {
                my $rule = $_[0]->rule;
                
                my $pos = $rule->value_position_for_property_name($property);
                unless ($pos) {
                    die "$property is not specified for this set!"
                }
                my $op = $rule->operator_for_property_name($property);
                unless ($op eq '=' or $op eq '') {
                    die "the value for $property is non-specific for this set!"                
                }
                my $value = $rule->specified_value_for_position($pos);
                $_[0]->{$property} = $value;
            }
        };
        
        no strict 'refs';
        
        *{$set_class_name . "::$property"}  = $accessor;
        
    }
    
    
    return $class_obj;
}

sub get_partitions {    
    my $self = shift;
    my %params = @_;
    my $partition_by = delete $params{partition_by} || [];
    $partition_by = [$partition_by] unless ref($partition_by);
    my $hint         = delete $params{-hint} || [];
    
    
    my $set_class = $self->class;

    my $rule = $self->rule;
    my @values = $rule->get_values;

    my $member_class_name = $self->member_class_name;
    my $logic_type = $self->rule_template->logic_type;
    my @base_property_names = $self->rule_template->_property_names;
    
    my @non_aggregate_properties = @$partition_by;
    my @aggregate_properties = @$hint;
    my $division_point = $#non_aggregate_properties;

    my $template = UR::BoolExpr::Template->get_by_subject_class_name_logic_type_and_logic_detail(
        $member_class_name,
        'And',
        join(",", @base_property_names, @non_aggregate_properties),
    );

    my $sql = $self->_generate_sql(
        $params{partition_by},         #group
        $params{-hint},                 #show
        $params{summary},                 #summary
        $params{rowlimit},
        $params{summary_placement}
    );
    
    my $k = $member_class_name->dbh->selectall_arrayref($sql);    
    my @subsets;
    $DB::single = 1;
    foreach my $row (@$k) {
        my $ss_rule = $template->get_rule_for_values(@values, @$row[0..$division_point]);
        my $set_instance = $set_class->get($ss_rule->id);
        @$set_instance{@aggregate_properties} = @$row[$division_point+1..$#$row];
        push @subsets, $set_instance;
    }
    
    return @subsets;
}

sub _generate_sql {
    # this is the old query generator from gscfind
    
    my $self = shift;
    my ($group, $show, $summaries, $rowlimit, $summary_placement) = @_;
    
    my @group = @$group;    
    my @show = defined $show ? @$show : ();
    #print Dumper(\@show);
    my @summaries = defined $summaries ? @$summaries : ();

    $DB::single = 1;

    my $rule = UR::BoolExpr->get($self->id);
    Dumper($rule);

    my $type_spec = $self->_get_legacy_gscfind_spec();
    my $spec = $self->_get_legacy_gscfind_spec();
    
    my $data_source = $spec->{data_source} || "oltp";
    my $aliases = $spec->{aliases};
    my $relationships = $spec->{relationships};

    # The group-by passed in at the "hint" should be shown, as well as the "show"
    # (that is, the aggregators)
    @show = (@group, @show);
    # Determine the fields to be shown.
    @show = @{ $spec->{default_show} } unless @show;

    # Some "show" fields are synonyms for a whole list of fields (i.e. "mini").
    # Flatten them.
    while (grep { ref($aliases->{$_}) eq 'ARRAY' } @show) {
        @show = map
            {
                my $val = $aliases->{$_};
                if (ref($val) eq 'ARRAY') {
                    # If the alias is an arrayref, flatten it
                    @$val
                }
                else {
                    $_
                }
            }
            @show;
    }

    # If the user has specified that summarizing should occur, determine how.
    for my $summary (@summaries) {
        for my $field (@$summary) {
            $field = $aliases->{$field};
        }
    }

    my %join;
    my %filters_by_join;
    my %join_for_fstring;
    my @filter_summary;
    my @filter_individual;
    my %filter_inside;

    # deconstruct the filters from the rule
    my $rule_template = $rule->get_rule_template;
    my @rvalues = $rule->get_values;

    my $conjunction = $rule_template->logic_type;
    my $subject_class = $rule_template->member_class_name;
    my @keys = $rule_template->_property_names;

    # pass 2:
    # extract sql building info from rule filters
    for my $i (0...$#rvalues) {
        my $fstring;
        
        # process the field name
        my @join_names;
        my $filter_inside = "";
        my $value_transformation = \&GSCFind::quote;
        
        my $param_name = $keys[$i];
        my $val = $rvalues[$i];
        
        my $key_name = $param_name;
        my $key_extension = undef;
        if($param_name =~ m/(.*?) (.*)/) {
            $key_name = $1;
            $key_extension = $2;
        }
        if (my $actual_name = $aliases->{$key_name}) {
            if (ref($actual_name)) {
                $value_transformation = $actual_name->{filter_value} if $actual_name->{filter_value};
                $actual_name = $actual_name->{filter};
            }
            $param_name = $actual_name;
        if ($key_extension) {
        $param_name .= " " . $key_extension;
        }
            @join_names = ($actual_name =~ /\b([^\W\d]\w+)\./g);
        }

        # process the operator
        if ($param_name =~ m/(.*) \[\]/) {
            $fstring = "";

            my @values = @{$val};
            while (my @more = splice(@values,0,1000)) {
                if ($fstring) {
                    $fstring .= "\n\tor "
                }
                $fstring .=
                    "$1 in ("
                    . join(",",
                            map {
                                s/\'//g;
                                $value_transformation->($_)
                            }
                            @more
                        )
                    . ")";
            }
        }
        elsif ($param_name =~ m/(.*) between/) {
             my ($a,$b) = @{$val};

            $a =~ s/\'//g;
            $b =~ s/\'//g;
            $a = $value_transformation->($a);
            $b = $value_transformation->($b);
            $fstring = "$1 between $a and $b\n";
        }
        elsif (!defined($val) ||
           length($val)==0) {
            if ($param_name =~ m/(.*) !=/) {
                $fstring = "$1 is not null\n"
            }
            else {
                $fstring = "$param_name is null\n"
            }
        }
        elsif ($param_name =~ /(.*) like(\-?)(.*?)/) {
            my $esc = $3 || '\\';
            my $value = $val;
            $value =~ s/_/${esc}_/g;
            $value = $value_transformation->($value);
            $fstring = "$1 like $value" . (defined $esc ? " ESCAPE '$esc'" : "") . "\n";
        }
         elsif ($param_name =~ m/(.*) !=/) {
         my $kval = $value_transformation->($val);
         $fstring = "$1 != $kval\n";
     } else {
         my $kval = $value_transformation->($val);
         $fstring = $param_name . " = " . $kval;
     }

        $fstring = _shift_text_left($fstring,2);

        for my $join_name (@join_names) {
            $join{$join_name} = $relationships->{$join_name};
            $filters_by_join{$join_name} ||= [];
            push @{ $filters_by_join{$join_name} }, $fstring;
            $join_for_fstring{$fstring} = $join_names[0];
        }

        my $field = $param_name;
        if($field =~ /(count|sum|min|max)\s*\(/i and not $field =~ /^\(select/) {
            push @filter_summary, $fstring
        }
        else {
            push @filter_individual, $fstring
        }
    }

    my %fshow;
    for my $field (@show) {
        my $actual_name = $aliases->{$field};
        if ($actual_name) {
            if (ref($actual_name)) {
                $actual_name = $actual_name->{show};
            }
            if (my @join_names = ($actual_name =~ /\b([^\W\d]\w+)\./g)) {
                for my $join_name (@join_names) {
                    $join{$join_name} = $relationships->{$join_name};
                }
            }
            $field = "$actual_name \"$field\"";
        }
        else {
            $actual_name = $field
        }
        if($field =~ /(count|sum|min|max)\s*\(/i and not $field =~ /^\(select/) {
        #if($field !~ /^\(select/) {
            $fshow{$field} = $actual_name;
        }
    }



    delete $join{$spec->{table_name}} if $spec->{table_name};

    # Post-process the joins.
    my %join_deps;
    my $hint;
    my @unchecked = keys %join;
    my @force_data_source;
    while (my $join_name = shift @unchecked) {
        my $data = $join{$join_name};
        unless (defined $data) {
            die "Failed to find relationship:$join_name!";
        }
        next unless defined($data);
        if (ref($data) eq 'CODE') {
            $join{$join_name} = $data = $data->(@{ $filters_by_join{$join_name} });
        }

        if (ref($data) eq 'HASH') {
            if ($data->{hint}) {
                $hint .= " " . $data->{hint};
            }
            $join{$join_name} = $data->{join_sql};
            if ($data->{additional_filters}) {
                push @filter_individual, @{ $data->{additional_filters} };
            }
            if ($data->{join_dep}) {
                $join_deps{$join_name} = $data->{join_dep};
                for my $additional_join_name (@{ $data->{join_dep} }) {
                    my $data = $join{$additional_join_name};
                    unless (defined $data) {
                        $data = $relationships->{$additional_join_name};
                        unless ($data) {
                            die "Failed to find relationship $additional_join_name!";
                        }
                        $join{$additional_join_name} = $data;
                    }
                    push @unchecked, $additional_join_name;
                }
            }
            if ($data->{force_data_source}) {
                push @force_data_source, $data->{force_data_source};
            }            
        }
        # Look for internal filters
        if ($join{$join_name} =~ /-- FILTER/ and $filters_by_join{$join_name}) {
            $filter_inside{$join_name} = 1;
        }
    }

    @filter_summary = map { s/^\s+//; s/\s+$//; $_ } @filter_summary;
    @filter_individual = map { s/^\s+//; s/\s+$//; $_ } @filter_individual;

    # This variable is always empty and should be removed from the code below.
    my %additional_join;

    # Formulate the SQL clauses.

    my $group_cols = "";
    my @non_function_cols; 

    my %non_function_cols;

    if (keys %fshow) {
        @non_function_cols =
            map { (/^(.+)\s+(\S+)\s*$/ ? $1 : $_ ) }
            grep { not $fshow{$_} }
            @show;
        %non_function_cols = map { $_ => 1 } @non_function_cols;
        $group_cols = join(", ",@non_function_cols,@group);
    }


    my $group_by = "";
    if ($group_cols) {
        $group_by = "group by "
        . (@summaries ? "rollup (" : "(")
        . $group_cols . ")\n";
    }

    # If the results are to be externally formatted, the grouping level when
    # using a "rollup" clause must be returned.

    #if (@summarize and @non_function_cols) {
    #    unshift @show,
    #        "("
    #        . join("+", map { "grouping($_)" } @non_function_cols)
    #        . ") GRP"
    #}

    my $having = "";
    my @summary_expressions;
    if (@summaries) {
        for my $summary (\@non_function_cols,@summaries) {
            my %summary = map { $_ => 1 } @$summary;
            my $expr = "("
                . join(" and ",
                        map {
                            "grouping($_) = " . ($summary{$_} ?  0 : 1)
                        }
                        @non_function_cols
                    )
                . ")";
            push @summary_expressions, $expr;
        }
        $having = "having (" . join("\n or ", @summary_expressions) . " )\n";
    }

    if (@filter_summary) {
        if ($having) {
            $having .= " and "
        }
        else {
            $having = "having "
        }
        $having .= join(" and ", @filter_summary[0..$#filter_summary]) . "\n";
    }
    else {
        $having = ""
    }

    # If "inner filters" are specified above, some filters affect a query which
    # is inside an inline view to which the main query joins.  Rewrite the join
    # clause to include the filters via find/replace.

    # When a join text block begins with "from", it is presumed to be overtaking
    # the standard start of the from clause, and to require an "ordered" hint.
    # This is for the case in which Oracle can't make a good query plan,
    # and we have to rewrite the joins in a particular order and give a hint to it.
    # It is only done for inline views with custom filtering which require initial
    # materialization to get a good plan.

    for my $join_name (keys %filter_inside) {
        my @inner_filters =
            @{ $filters_by_join{$join_name} };
        if (@inner_filters) {
            my $where = "where "
                . join("and ",
                    map { s/\b$join_name\.//g; $_ }
                    @inner_filters
                );
            chomp $where;
            $where .= "\n";
            $join{$join_name} =~ s/-- FILTER/$where/;
            if ($join{$join_name} =~ /^\s*from\b/) {
                $hint .= " ordered";
            }
        }
    }

    # If one of the relationships starts with "from", it takes
    # precedence in the query over the default entity table, and
    # the query is "ordered".  Find this relationship if it is present.

    my $ordered_from;

    # Put all of the joins in order.

    my %all_joins = (%join, %additional_join);
    my @join_names_unordered = keys %all_joins;
    my @join_names_ordered;

    my %joins_added;
    my $add_join;
    
    $DB::single = 1;
    $add_join = _recursive( sub {
        my $join_name = shift;
        if (my $deps = $join_deps{$join_name}) {
            for my $dep (@$deps) {
                $REC->($dep);
            }
        }
        unless ($joins_added{$join_name}) {
            my $clause = $all_joins{$join_name};

            if (length($clause)) {
                $clause = _shift_text_left($clause);
                $all_joins{$join_name} = $clause;
            }
            elsif (not defined $clause) {
                warn "Script error: cannot join to '$join_name'.  Contact Informatics.\n";                
            }

            if ($clause =~ /^\s*from\b/) {
                $ordered_from = $clause;
            }
            else {
                push @join_names_ordered, $join_name;
            }

            $joins_added{$join_name} = 1;
        }
    });

    for my $join_name (@join_names_unordered) {
        $add_join->($join_name);
    }

    # Write the SQL clauses.

    my $select = "select" . ($group_by ? "" : " distinct") . "\n"
                . ($hint ? "    /*+ $hint */\n" : "")
                . join(",\n", map { _shift_text_left($_,4) } @show)
                . "\n";

    my $from;
    if ($ordered_from) {
        $from = $ordered_from;
    }
    elsif ($spec->{from_clause}) {
        $from = $spec->{from_clause};
    }
    elsif ($spec->{table_name}) {
        $from = "from " . $spec->{table_name} . " ";
    }
    else {
        $from = "from " . $type_spec . " ";
    }
    chomp $from;
    $from = _shift_text_left($from);

    $from .=
        " \n"
        . join(" \n",@all_joins{@join_names_ordered});

    if (@force_data_source) {
        my %force_data_source = map { $_ => 1 } @force_data_source;
        if (keys(%force_data_source) > 1) {
            die "This query combines fields which are are incompatible.  Contact Informatics for help.";
        }
        ($data_source) = keys(%force_data_source);
    }
    if ($data_source eq "oltp") {
        $from =~ s/\@oltp//g;
    }
    elsif ($data_source eq "warehouse") {
        $from =~ s/\@dw//g;
    }
    elsif ($data_source eq "olap") {
        $from =~ s/\@olap//g;
    }
    elsif ($data_source eq "mg") {
        $from =~ s/\@mg//g;
    }
    else {
        die "Unrecognized data source: $data_source!  Contact Informatics.";
    }
    

    chomp $from;
    chomp $from;
    $from .= "\n";

    my $where;
    if ($rowlimit) {
        push @filter_individual, "rownum <= $rowlimit\n"
    }

    if (my @filter_in_where_clause =
        grep {
            my $join = $join_for_fstring{$_};
            ($join ? !$filter_inside{$join} : 1)
        }
        @filter_individual
    ) {
        $where = _shift_text_left(join("\nand ",@filter_in_where_clause),2);
        $where =~ s/^  //;
        $where = "where " . $where;
        chomp $where;
        $where .= "\n";
    }
    else {
        $where = ""
    }

    my $order_by;
    if (@summary_expressions and $summary_placement =~ /^(top|bottom)/) {
        my $n;
        $order_by =
            "order by (case\n"
            . join("", map { " when $_ then " . ++$n . "\n" } @summary_expressions)
            . "end) " . ($1 eq "bottom" ? "asc" : "desc")
            . ", $group_cols\n";
    }
    elsif ($group_cols) {
        $order_by = "order by $group_cols\n";
    }
    else {
        my $order = $show[0];
        $order =~ s/\s+\S+\s*$//;
        $order_by = "order by $order\n";
    }


    # Assemble the SQL

    my $sql = "\n"
        . $select
        . $from
        . $where
        . $group_by
        . $having
        . $order_by;

}

sub _property_isa_aggregator {
    my $self = shift;
    my $field = shift;

    my $spec = $self->_get_legacy_gscfind_spec();
    my $field_spec = $spec->{aliases}->{$field};
    
    if (ref($field_spec) eq "HASH") {
        $field_spec = $field_spec->{show};
    }

    return ($field_spec =~ /(count|sum|min|max)\s*\(/i and not $field =~ /^\(select/);
}

sub _shift_text_left  {
    my $clause = shift;
    my $indent = shift;
    $indent = 0 if not defined $indent;

    my $indent_string = ' ' x $indent;

    my @lines = split(/\n/,$clause);
    my $min_space;
    for my $line (@lines) {
        if ($line =~ /^(\s*)\S/) {
            my $spc = $1;
            unless (defined($min_space) and $min_space < length($spc)) {
                $min_space = length($spc);
                last if $min_space == 0;
            }
        }
    }
    if ($min_space) {
        no warnings;
        for (@lines) { $_ = substr($_,$min_space); }
    }
    $clause = join("\n", map { $indent_string . $_ } grep { defined($_) and /\S/ } @lines);
    return $clause;
}

1;
