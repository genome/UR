package UR::DataSource::RDBMS;
use strict;
use warnings;
use Scalar::Util;
use File::Basename;

require UR;

UR::Object::Type->define(
    class_name => 'UR::DataSource::RDBMS',
    is => ['UR::DataSource','UR::Singleton'],
    english_name => 'ur datasource rdbms',
    is_abstract => 1,
    properties => [
        _all_dbh_hashref                 => { type => 'HASH',       len => undef, is_transient => 1 },
        _default_dbh                     => { type => 'DBI::db',    len => undef, is_transient => 1 },
        _last_savepoint                  => { type => 'String',     len => undef, is_transient => 1 },
    ],
    doc => 'A logical DBI-based database, independent of prod/dev/testing considerations or login details.',
);

sub get_class_meta_for_table {
    my $self = shift;
    my $table = shift;
    my $table_name = $table->table_name;

    return $self->get_class_meta_for_table_name($table_name);
}

sub get_class_meta_for_table_name {
    my($self,$table_name) = @_;
    
    # There is an unique constraint on classes, but only those which use
    # tables in an RDBMS, which dicates that there can be only two for
    # a given table in a given data source: one for the ghost and one
    # for the regular entity.  We can't just fix this with a unique constraint
    # since classes with a null data source would be lost in some queries.
    my @class_meta =
        grep { not $_->class_name->isa("UR::Object::Ghost") }
        UR::Object::Type->get(
            table_name => $table_name,
            data_source => $self->class,
        );
    
    unless (@class_meta) {
        # This will load every class in the namespace on the first execution :(
        #$DB::single = 1;
        @class_meta =
            grep { not $_->class_name->isa("UR::Object::Ghost") }
            UR::Object::Type->get(
                table_name => $table_name,
                data_source => $self->class,
            );
    }

    $self->context_return(@class_meta);
}

sub dbi_data_source_name {    
    my $self = shift->_singleton_object;
    my $driver  = $self->driver;    
    my $server  = $self->server;
    unless ($driver) {
        Carp::confess("Cannot resolve a dbi_data_source_name with an undefined driver()");
    }    
    unless ($server) {
        Carp::confess("Cannot resolve a dbi_data_source_name with an undefined server()");
    }
    return 'dbi:' . $driver . ':' . $server;
}

sub get_default_dbh {    
    my $self = shift->_singleton_object;    
    my $dbh = $self->_default_dbh;
    unless ($dbh && $dbh->{Active}) {
        $dbh = $self->create_dbh();
        $self->_default_dbh($dbh);
    }    
    return $dbh;
}

sub has_default_dbh {
    my $self = shift->_singleton_object;
    return 1 if $self->_default_dbh;
    return;
}

sub disconnect_default_dbh {
    my $self = shift->_singleton_object;
    my $dbh = $self->_default_dbh;
    unless ($dbh) {
        Carp::cluck("Cannot disconnect.  Not connected!");
        return;
    }
    $dbh->disconnect;
    $self->_default_dbh(undef);
    return $dbh;
}

sub set_all_dbh_to_inactive_destroy {
    my $self = shift->_singleton_object;
    my $dbhs = $self->_all_dbh_hashref;    
    for my $k (keys %$dbhs) {
        $dbhs->{$k}->{InactiveDestroy} = 1;
        delete $dbhs->{$k};
    }
    my $dbh = $self->_default_dbh;
    if ($dbh) {
        $dbh->disconnect;
        $self->_default_dbh(undef);
    }
    return 1;
}

sub get_for_dbh {
    my $class = shift;
    my $dbh = shift;
    my $ds_name = $dbh->{"private_UR::DataSource::RDBMS_name"};
    my $ds = UR::DataSource->get($ds_name);
    return $ds;
}

sub has_changes_in_base_context {
    shift->has_default_dbh;
    # TODO: actually check, as this is fairly conservative
    # If used for switching contexts, we'd need to safely rollback any transactions first.
}


sub _dbi_connect_args {
    my $self = shift;

    my @connection;
    $connection[0] = $self->dbi_data_source_name;
    $connection[1] = $self->login;
    $connection[2] = $self->auth;
    $connection[3] = { AutoCommit => 0, RaiseError => 0 };

    return @connection;
}

sub create_dbh {
    my $self = shift->_singleton_object;
    
    # invalid command-line parameters may contain typos of things like no-commit
    unless (UR::Command::Param->argv_has_been_processed_successfully) {
        die("Invalid command-line parameters!: @ARGV\n");
    }
    
    # get connection information
    my @connection = $self->_dbi_connect_args();
    
    # connect
    my $dbh = UR::DBI->connect(@connection);
    $dbh or
        Carp::confess("Failed to connect to the database!\n"
            . UR::DBI->errstr . "\n");

    # used for reverse lookups
    $dbh->{'private_UR::DataSource::RDBMS_name'} = $self->class;

    # this method may be implemented in subclasses to do extra initialization
    if ($self->can("_init_created_dbh")) {
        unless ($self->_init_created_dbh($dbh)) {
            $dbh->disconnect;
            die "Failed to initialize new database connection!\n"
                . $self->error_message . "\n";
        }
    }

    # store the handle in a hash, since it's not a UR::Object
    my $all_dbh_hashref = $self->_all_dbh_hashref;
    unless ($all_dbh_hashref) {
        $all_dbh_hashref = {};
        $self->_all_dbh_hashref($all_dbh_hashref);
    }
    $all_dbh_hashref->{$dbh} = $dbh;
    Scalar::Util::weaken($all_dbh_hashref->{$dbh});
    
    return $dbh;
}

sub _init_created_dbh {
    # override in sub-classes
    1;
}

sub _get_table_names_from_data_dictionary {
    my $self = shift->_singleton_object;        
    if (@_) {
        Carp::confess("get_tables does not currently take filters!  FIXME.");
    }    
    my $dbh = $self->get_default_dbh;
    my $owner = $self->owner;    

    # FIXME  This will fix the immediate problem of getting classes to be created out of 
    # views.  We still need to somehow mark the resulting class as read-only

    my $sth = $dbh->table_info("%", $owner, "%", "TABLE,VIEW");
    my $table_name;
    $sth->bind_col(3,\$table_name);
    my @names;
    while ($sth->fetch) {
        next if $self->_ignore_table($table_name);
        $table_name =~ s/"|'//g;  # Postgres puts quotes around entities that look like keywords
        push @names, $table_name;
    }
    return @names;
}


sub get_table_names {
    map { $_->table_name } shift->get_tables(@_);
}

sub get_tables {
    my $class = shift->_singleton_class_name;
    return UR::DataSource::RDBMS::Table->get(data_source => $class);
}

# TODO: make "env" an optional characteristic of a class attribute
# for all of the places we do this crap...

sub access_level {
    my $self = shift;
    my $env = $self->_method2env("access_level");    
    if (@_) {
        if ($self->has_default_dbh) {
            Carp::confess("Cannot change the db access level for $self while connected!");
        }
        $ENV{$env} = lc(shift);
    }
    else {
        $ENV{$env} ||= "ro";
    }
    return $ENV{$env};
}

sub _method2env {
    my $class = shift;
    my $method = shift;
    unless ($method =~ /^(.*)::([^\:]+)$/) {
        $class = ref($class) if ref($class);
        $method = $class . "::" . $method;
    }
    $method =~ s/::/__/g;
    return $method;
}

sub resolve_class_name_for_table_name {
    my $self = shift->_singleton_class_name;
    my $table_name = shift;
    my $relation_type = shift;   # Should be 'TABLE' or 'VIEW'

    # When a table_name conflicts with a reserved word, it ends in an underscore.
    $table_name =~ s/_$//;
    
    my $namespace = $self->get_namespace;
    my $vocabulary = $namespace->get_vocabulary;

    my @words;
    $vocabulary = 'UR::Vocabulary' unless eval { $vocabulary->get_class_object };
    if ($vocabulary) {
        @words = 
            map { $vocabulary->convert_to_title_case($_) } 
            map { $vocabulary->plural_to_singular($_) }
            map { lc($_) }
            split("_",$table_name);
    } else {
        @words = 
            map { ucfirst(lc($_)) }
            split("_",$table_name);
    }

    if ($self->can('_resolve_class_name_for_table_name_fixups')) {
        @words = $self->_resolve_class_name_for_table_name_fixups(@words);
    }
        
    my $class_name;
    my $addl;
    if ($relation_type && $relation_type =~ m/view/i) {
        $addl = 'View::';
    } else {
        # Should just be for tables, temp tables, etc
        $addl = '';
    }
    $class_name = $namespace . "::" . $addl . join("",@words);
    return $class_name;
}

sub resolve_type_name_for_table_name {
    my $self = shift->_singleton_class_name;
    my $table_name = shift;
    
    my $namespace = $self->get_namespace;
    my $vocabulary = $namespace->get_vocabulary;
    $vocabulary = 'UR::Vocabulary' unless eval { $vocabulary->get_class_object };
    
    my $vocab_obj = eval { $vocabulary->get_class_object };
    my @words =         
    (
        (
            map { $vocabulary->plural_to_singular($_) }
            map { lc($_) }
            split("_",$table_name)
        )
    );
        
    my $type_name =  join(" ",@words);
    return $type_name;
}

sub resolve_property_name_for_column_name {
    my $self = shift->_singleton_class_name;
    my $column_name = shift;
    
    my @words =                 
        map { lc($_) }
        split("_",$column_name);
        
    my $type_name =  join("_",@words);
    return $type_name;
}

sub resolve_attribute_name_for_column_name {
    my $self = shift->_singleton_class_name;
    my $column_name = shift;
    
    my @words =                 
        map { lc($_) }
        split("_",$column_name);
        
    my $type_name =  join(" ",@words);
    return $type_name;
}

sub can_savepoint {
    my $class = ref($_[0]);
    die "Class $class didn't supply can_savepoint()";
}

sub set_savepoint {
    my $class = ref($_[0]);
    die "Class $class didn't supply set_savepoint, but can_savepoint is true";
}

sub rollback_to_savepoint {
    my $class = ref($_[0]);
    die "Class $class didn't supply rollback_to_savepoint, but can_savepoint is true";
}



# Derived classes should define a method to return a ref to an array of hash refs
# describing all the bitmap indicies in the DB.  Each hash ref should contain
# these keys: table_name, column_name, index_name
# If the DB dosen't support bitmap indicies, it should return an empty listref
# This is used by the part that writes class defs based on the DB schema, and 
# possibly by sync_database()
# Implemented methods should take one optional argument: a table name
sub bitmap_index_info {
    my $class = shift;
    Carp::confess("Class $class didn't define its own bitmap_index_info() method");
}


# Derived classes should define a method to return a ref to a hash keyed by constraint
# names.  Each value holds a listref of hashrefs containing these keys:
# CONSTRAINT_NAME and COLUMN_NAME
sub unique_index_info {
    my $class = shift;
    Carp::confess("Class $class didn't define its own unique_index_info() method");
}

sub autogenerate_new_object_id_for_class_name {
    # The sequences in the database are named by a naming convention which allows us to connect them to the table
    # whose surrogate keys they fill.  Look up the sequence and get a unique value from it for the object.
    # If and when we save, we should not get any integrity constraint violation errors.

    my $self = shift;
    my $class_name = shift;

    if ($self->use_dummy_autogenerated_ids) {
        return $self->next_dummy_autogenerated_id;
    }

    my $class = UR::Object::Type->get(class_name => $class_name);
    my $table_name;
    unless ($table_name) {
        for my $parent_class_name ($class_name, $class_name->inheritance) {
            # print "checking $parent_class_name (for $class_name)\n";
            my $parent_class = UR::Object::Type->get(class_name => $parent_class_name);
            # print "object $parent_class\n";
            next unless $parent_class;
            if ($table_name = $parent_class->table_name) {
                # print "found table $table_name\n";
                last;
            }
        }
    }

    my $table = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self);

    unless ($table_name && $table) {
        Carp::confess("Failed to find a table for class $class_name!");
    }

    my @keys = $table->primary_key_constraint_column_names;
    my $key;
    if (@keys > 1) {
        Carp::confess("Tables with multiple primary keys (i.e." . $table->table_name  . " @keys) cannot have a surrogate key created from a sequence.");
    }
    elsif (@keys == 0) {
        Carp::confess("No primary keys found for table " . $table->table_name . "\n");
    }
    else {
        $key = $keys[0];
    }

    my $sequence = $self->_get_sequence_name_for_table_and_column($table_name, $key);

    my $new_id = $self->_get_next_value_from_sequence($sequence);
    return $new_id;
}


sub _get_sequence_name_for_table_and_column {
    my($self,$table_name,$column_name) = @_;

    # The default is to take the column name (should be a primary key from a table) and
    # change the _ID at the end of the column name with _SEQ
    $column_name =~ s/_ID/_SEQ/;
    return $column_name;
}


sub _generate_loading_templates_arrayref {
    # Make a template set of templates from @sql_cols;
    # Each entry represents a table alias in the query.
    # This accounts for multiple occurrances of the same 
    # table in a join, by grouping by alias instead of
    # table.
    
    my $class = shift;
    my $sql_cols = shift;

    return [];    

    use strict;
    use warnings;
    
    my %templates;
    my $pos = 0;
    for my $col_data (@$sql_cols) {
        my ($class_obj, $prop, $table_alias, $object_num, $class_name) = @$col_data;
        my $template = $templates{$table_alias};
        unless ($template) {
            $template = {
                object_num => $object_num,
                table_alias => $table_alias,
                data_class_name => $class_obj->class_name,
                final_class_name => $class_name || $class_obj->class_name,
                property_names => [],                    
                column_positions => [],                    
                id_property_names => undef,
                id_column_positions => [],
                id_resolver => undef, # subref
            };
            $templates{$table_alias} = $template;
        }
        push @{ $template->{property_names} }, $prop->property_name;
        push @{ $template->{column_positions} }, $pos;
        $pos++;            
    }
    
    # Post-process the template objects a bit to get the exact id positions.
    my @templates = values %templates;
    for my $template (@templates) {               
        my @id_property_names;
        for my $id_class_name ($template->{data_class_name}, $template->{data_class_name}->inheritance) {
            my $id_class_obj = UR::Object::Type->get(class_name => $id_class_name);
            last if @id_property_names = $id_class_obj->id_property_names;
        }
        $template->{id_property_names} = \@id_property_names;
        
        my @id_column_positions;
        for my $id_property_name (@id_property_names) {
            for my $n (0..$#{ $template->{property_names} }) {
                if ($template->{property_names}[$n] eq $id_property_name) {
                    push @id_column_positions, $template->{column_positions}[$n];
                    last;
                }
            }
        }
        $template->{id_column_positions} = \@id_column_positions;            
        
        if (@id_column_positions == 1) {
            $template->{id_resolver} = sub {
                return $_[0][$id_column_positions[0]];
            }
        }
        elsif (@id_column_positions > 1) {
            my $class_name = $template->{data_class_name};
            $template->{id_resolver} = sub {
                my $self = shift;
                return $class_name->composite_id(@$self[@id_column_positions]);
            }                    
        }
        else {
            use Data::Dumper;
            die "No id column positions for template " . Dumper($template);
        }             
    }        

    return \@templates;        
}

sub create_iterator_closure_for_rule_template_and_values {
    my ($self, $rule_template, @values) = @_;
    my $rule = $rule_template->get_rule_for_values(@values);
    return $self->create_iterator_closure_for_rule($rule);
}

sub create_iterator_closure_for_rule {

    my ($self, $rule) = @_; 

    my ($rule_template, @values) = $rule->get_rule_template_and_values();    
    my $template_data = $self->_get_template_data_for_loading($rule_template); 

    #
    # the template has general class data
    #
    
    my $class_name                                  = $template_data->{class_name};
    my $class = $class_name;    
    
    my @lob_column_names                            = @{ $template_data->{lob_column_names} };
    my @lob_column_positions                        = @{ $template_data->{lob_column_positions} };    
    my $query_config                                = $template_data->{query_config}; 
    
    my $post_process_results_callback               = $template_data->{post_process_results_callback};

    #
    # the template has explicit template data
    #  

    my $select_clause                              = $template_data->{select_clause};
    my $select_hint                                = $template_data->{select_hint};
    my $from_clause                                = $template_data->{from_clause};
    my $where_clause                               = $template_data->{where_clause};
    my $connect_by_clause                          = $template_data->{connect_by_clause};    
    my $order_by_clause                             = $template_data->{order_by_clause};
    
    my $sql_params                                  = $template_data->{sql_params};
    my $filter_specs                                = $template_data->{filter_specs};
    
    my @property_names_in_resultset_order           = @{ $template_data->{property_names_in_resultset_order} };
    
    # TODO: we get 90% of the way to a full where clause in the template, but 
    # actually have to build it here since ther is no way to say "in (?)" and pass an arrayref :( 
    # It _is_ possible, however, to process all of the filter specs with a constant number of params.
    # This would optimize the common case.   
    my @all_sql_params = @$sql_params;
    for my $filter_spec (@$filter_specs) {
        my ($expr_sql, $operator, $value_position) = @$filter_spec;
        my $value = $values[$value_position];
        my ($more_sql, @more_params) = 
            $self->_extend_sql_for_column_operator_and_value($expr_sql, $operator, $value);
            
        $where_clause .= ($where_clause ? "\nand " : ($connect_by_clause ? "start with " : "where "));
        
        if ($more_sql) {
            $where_clause .= $more_sql;
            push @all_sql_params, @more_params;
        }
        else {
            # error
            return;
        }
    }

    # The full SQL statement for the template, besides the filter logic, is built here.    
    my $sql = "\nselect ";
    if ($select_hint) {
        $sql .= $select_hint . " ";
    }
    $sql .= $select_clause;
    $sql .= "\nfrom $from_clause";
    $sql .= "\n$where_clause" if length($where_clause);
    $sql .= "\n$connect_by_clause" if $connect_by_clause;           
    $sql .= "\n$order_by_clause"; 

    my $dbh = $self->get_default_dbh;    
    my $sth = $dbh->prepare($sql,$query_config);
    unless ($sth) {
        $class->error_message("Failed to prepare SQL $sql\n" . $dbh->errstr . "\n");
        Carp::confess($class->error_message);
    }    
    unless ($sth->execute(@all_sql_params)) {
        $class->error_message("Failed to execute SQL $sql\n" . $sth->errstr . "\n" . Dumper(\@$sql_params) . "\n");
        Carp::confess($class->error_message);
    }    

    die unless $sth;    

    # buffers for the iterator
    my $next_db_row;
    my $pending_db_object_data;
    my $iterator = sub {
    
        $next_db_row = $sth->fetchrow_arrayref;
        
        unless ($next_db_row) {
            $sth->finish;
            $sth = undef;
            return;
        } 
        
        # this handles things lik BLOBS, which have a special interface to get the 'real' data
        if ($post_process_results_callback) {
            $next_db_row = $post_process_results_callback->($next_db_row);
        }
        
        # this is used for automated re-testing against a private database
        $self->_CopyToAlternateDB($class,$dbh,$next_db_row) if ($ENV{'UR_TEST_FILLDB'});                                
        
        # translate column hash into a hash structured like our new object
        $pending_db_object_data = {};
        @$pending_db_object_data{@property_names_in_resultset_order} = @$next_db_row;    
        
        return $pending_db_object_data;
    }; # end of iterator closure
    
    return $iterator;
}

# This allows the size of an autogenerated IN-clause to be adjusted.
# The limit for Oracle is 1000, and a bug requires that, in some cases
# we drop to 250.
my $in_clause_size_limit = 250;        

# This method is used when generating SQL for a rule template, in the joins
# and also on a per-query basis to turn specific values into a where clause
sub _extend_sql_for_column_operator_and_value {
    my ($self, $expr_sql, $op, $val, $escape) = @_;

    if ($op eq '[]' and not ref($val) eq 'ARRAY') {
        $DB::single = 1;
        $val = [];
    }    

    my $sql; 
    my @sql_params;
    
    if ($op eq '' or $op eq '=' or $op eq 'eq') {
        $sql .= $expr_sql;
        if ($self->_value_is_null($val))
        {
            $sql = "$expr_sql is NULL";
        }
        else
        {
            $sql = "$expr_sql = ?";
            push @sql_params, $val;
        }        
    }
    elsif ($op eq '[]' or $op =~ /in/i) {
        no warnings 'uninitialized';
        unless (@$val)
        {
            # an empty list was passed-in.
            # since "in ()", like "where 1=0", is self-contradictory,
            # there is no data to return, and no SQL required
            Carp::carp("Null in-clause passed to default_load_sql");
            return;
        }
        
        my @list = sort @$val;
        my $has_null = ( (grep { length($_) == 0 } @list) ? 1 : 0);
        my $wrap = ($has_null or @$val > $in_clause_size_limit ? 1 : 0);
        my $cnt = 0;
        $sql .= "\n(\n   " if $wrap;
        while (my @set = splice(@list,0,$in_clause_size_limit))
        {
            $sql .= "\n   or " if $cnt++;
            $sql .= $expr_sql;
            $sql .= " in (" . join(",",map { "'$_'" } @set) . ")";
        }
        if ($has_null) {
            $sql .= "\n  or $expr_sql is null"
        }
        $sql .= "\n)\n" if $wrap;
    }       
    elsif($op =~ /^(like|not like|in|not in|\<\>|\<|\>|\=|\<\=|\>\=)$/i ) {
        # SQL operator.  Use this directly.
        $sql .= "$expr_sql $op ?";
        push @sql_params, $val;        
        if($op =~ /like/i) {
            $escape ||= '\\';
            $sql .= " escape '" . $escape . "'";
        }
    } elsif($op =~ /^(ne|\!\=)$/i) {                
        # Perlish inequality.  Special SQL to handle this.
        if (not defined($val)) {
            # ne undef =~ is not null
            $sql .= "$expr_sql is not null";
            pop @sql_params;
        }
        elsif ($op =~ /^(ne|\!\=)$/i) {
            # ne $v =~ should match everything but $v, including nulls
            # != is the same, and will rely on is_loaded to 
            # filter out any cases where "hello" != "goodbye" returns
            # but Perl wants to exclude the value because they match numerically.
            $sql .= "( $expr_sql != ?" 
                    .  " or $expr_sql is null)";                                                     
            push @sql_params, $val;
        }                                
    } elsif ($op eq "between") {
        $sql .= "$expr_sql $op ? and ?";
        push @sql_params, @$val;
    } else {
        # Something else?
        die "Unkown operator $op!";
    }
        
    if (@sql_params > 256) {
        Carp::confess("A bug in Oracle causes queries using > 256 placeholders to return incorrect results.");
    }

    return ($sql, @sql_params)
}

sub _value_is_null {
    # this is a separate method since some databases, like Oracle, treat empty strings as null values
    my ($self, $value) = @_;
    return 1 if not defined $value;
    return if not ref($value);
    if (ref($value) eq 'HASH') {
        if ($value->{operator} eq '=' or $value->{operator} eq 'eq') {
            if (not defined $value->{value}) {
                return 1;
            }
            else {
                return;
            }
        }
    }
    return;
}

sub _resolve_ids_from_class_name_and_sql {
    my $self = shift;
    
    my $class_name = shift;
    my $sql = shift;
        
    my $query;
    my @params;
    if (ref($sql) eq "ARRAY") {
        ($query, @params) = @{$sql};
    } else {
        $query = $sql;
    }
    
    my $class_meta = $class_name->get_class_object;
    my @id_columns = 
        map {
            $class_meta->get_property_object(property_name => $_)->column_name
        } 
        $class_meta->id_property_names;

    # query for the ids
    
    my $dbh = $self->get_default_dbh();
    
    my $sth = $dbh->prepare($query);

    unless ($sth) {
        confess("could not prepare query $query");
    }
    $sth->execute(@params);
    my $data;

    my @id_fetch_set;
    
    while ($data = $sth->fetchrow_hashref()) {
	#ensure everything is uppercased. this is totally a hack right now but it makes sql queries work again.
	foreach my $key (keys %$data) {
		$data->{uc($key)} = delete $data->{$key};
	}
        my @id_vals = map {$data->{uc($_)}} @id_columns;
        my $cid = $class_name->composite_id(@id_vals);
        push @id_fetch_set, $cid;       
    }
    
    return @id_fetch_set;
}

sub _reclassify_object_loading_info_for_new_class {
    my $self = shift;
    my $loading_info = shift;
    my $new_class = shift;

    my $new_info;
    %$new_info = %$loading_info;

    foreach my $target_class (keys %$loading_info) {

        my $target_class_rules = $loading_info->{$target_class};
        foreach my $rule_id (keys %$target_class_rules) {
            my $pos = index($rule_id,'/');
            $new_info->{$target_class}->{$new_class . "/" . substr($rule_id,$pos+1)} = 1;
        }
    }

    return $new_info;
}

sub _get_object_loading_info {
    my $self = shift;
    my $obj = shift;
    my %param_load_hash;
    if ($obj->{load} and $obj->{load}->{param_key}) {
        while (my ($class,$param_strings_hashref) = each %{ $obj->{load}->{param_key} }) {
            for my $param_string (keys %$param_strings_hashref) {
                $param_load_hash{$class}{$param_string}=
                    $UR::Object::all_params_loaded->{$class}{$param_string};
            }
        }
    }
    return \%param_load_hash;
}

sub _add_object_loading_info {
    my $self = shift;
    my $obj = shift;
    my $param_load_hash = shift;
    no strict 'refs';    
    for my $class (keys %$param_load_hash) {
        my $param_data = $param_load_hash->{$class};
        for my $param_string (keys %$param_data) {
            $obj->{load}{param_key}{$class}{$param_string}
                 = $param_data->{$param_string};
        }
    }
}

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


sub _CopyToAlternateDB {
    # This is used to copy data loaded from the primary database into
    # a secondary database.  One use is for setting up an alternate DB
    # for testing by priming it from data from the "live" DB
    #
    # This is called from inside load() when the env var UR_TEST_FILLDB
    # is set.  For now, this alternate DB is always an SQLIte DB, and the
    # value of the env var is the base name of the file used as its storage.

    my($self,$load_class_name,$orig_dbh,$data) = @_;

    our %ALTERNATE_DB;
    my $dbname = $orig_dbh->{'Name'};

    my $dbh;
    if ($ALTERNATE_DB{$dbname}->{'dbh'}) {
        $dbh = $ALTERNATE_DB{$dbname}->{'dbh'};
    } else {
        my $filename = sprintf("%s.%s.sqlite", $ENV{'UR_TEST_FILLDB'}, $dbname);

        # FIXME - The right way to do this is to create a new UR::DataSource::SQLite object instead of making a DBI object directly
        unless ($dbh = $ALTERNATE_DB{$dbname}->{'dbh'} = DBI->connect("dbi:SQLite:dbname=$filename","","")) {
            $self->error_message("_CopyToAlternateDB: Can't DBI::connect() for filename $filename" . $DBI::errstr);
            return;
        }
        $dbh->{'AutoCommit'} = 0;
    }

    # Find out what tables this query will require
    my @isa = ($load_class_name);
    my(%tables,%class_tables);
    while (@isa) {
        my $class = shift @isa;
        next if $class_tables{$class};

        my $class_obj = $class->get_class_object;
        next unless $class_obj;

        my $table_name = $class_obj->table_name;
        next unless $table_name;
        $class_tables{$class} = $table_name;

        foreach my $col ( $class_obj->column_names ) {
            # FIXME Why are some of the returned column_names undef?
            next unless defined($col); # && defined($data->{$col});
            $tables{$table_name}->{$col} = $data->{$col} 
        }
        {   no strict 'refs';
            my @parents = @{$class . '::ISA'};
            push @isa, @parents;
        }
    }
    
    # For each parent class with a table, tell it to create itself
    foreach my $class ( keys %class_tables ) {
        next if (! $class_tables{$class} || $ALTERNATE_DB{$dbname}->{'tables'}->{$class_tables{$class}}++);

        my $class_obj = $class->get_class_object();
        $class_obj->mk_table($dbh);
        #unless ($class_obj->mk_table($dbh)) {
        #    $dbh->rollback();
        #    return undef;
        #}
    }

    # Insert the data into the alternate DB
    foreach my $table_name ( keys %tables ) {
        my $sql = "INSERT INTO $table_name ";

        my $num_values = (values %{$tables{$table_name}});
        $sql .= "(" . join(',',keys %{$tables{$table_name}}) . ") VALUES (" . join(',', map {'?'} (1 .. $num_values)) . ")";
        my $sth = $dbh->prepare_cached($sql);
        unless ($sth) {
            $self->error_message("Error in prepare to alternate DB: $DBI::errstr\nSQL: $sql");
            $dbh->rollback();
            return undef;
        }

        unless ( $sth->execute(values %{$tables{$table_name}}) ) {
            $self->warning_message("Can't insert into $table_name in alternate DB: ".$DBI::errstr."\nSQL: $sql\nPARAMS: ".
                                   join(',',values %{$tables{$table_name}}));

            # We might just be inserting data that's already there...
            # This is the error message sqlite returns
            if ($DBI::errstr !~ m/column (\w+) is not unique/i) {
                $dbh->rollback();
                return undef;
            }
        }
    }

    $dbh->commit();
    
    1;
}

sub _sync_database {
    my $self = shift;
    my %params = @_;
    
    my $changed_objects = delete $params{changed_objects};
    my %objects_by_class_name;
    for my $obj (@$changed_objects) {
        my $class_name = ref($obj);
        $objects_by_class_name{$class_name} ||= [];
        push @{ $objects_by_class_name{$class_name} }, $obj;
    }

    my $dbh = $self->get_default_dbh;    

    #
    # Determine what commands need to be executed on the database
    # to sync those changes, and categorize them by type and table.
    #

    # As we iterate through changes, keep track of all of the involved tables.
    my %all_tables;      # $all_tables{$table_name} = $number_of_commands;
    
    # Make a hash for each type of command keyed by table name.
    my %insert;          # $insert{$table_name} = [ $change1, $change2, ...];
    my %update;          # $update{$table_name} = [ $change1, $change2, ...];
    my %delete;          # $delete{$table_name} = [ $change1, $change2, ...];

    # Make a master hash referencing each of the above.
    # $explicit_commands_by_type_and_table{'insert'}{$table} = [ $change1, $change2 ...]
    my %explicit_commands_by_type_and_table = (
        'insert' => \%insert,
        'update' => \%update,
        'delete' => \%delete
    );

    # Build the above data structures.
    {
        no warnings;
        for my $class_name (sort keys %objects_by_class_name) {
            for my $obj (@{ $objects_by_class_name{$class_name} }) {
                my @commands = $self->_default_save_sql_for_object($obj);
                next unless @commands;
                
                for my $change (@commands)
                {
                    #$commands{$change} = $change;
    
                    # Example change:
                    # { type => 'update', table_name => $table_name,
                    # column_names => \@changed_cols, sql => $sql,
                    # params => \@values, class => $table_class, id => $id };
    
                    # There are often multiple changes per object, espeically
                    # when the object is spread across multiple tables because of
                    # inheritance.  We classify each change by the table and
                    # the class immediately associated with the table, even if
                    # the class in an abstract parent class on the object.
                    my $table_name = $change->{table_name};
                    my $id = $change->{id};                    
                    $all_tables{$table_name}++;
                    my $table = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self) ||
                                UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => 'UR::DataSource::Meta');
                    
                    if ($change->{type} eq 'insert')
                    {
                        push @{ $insert{$change->{table_name}} }, $change;
                    }
                    elsif ($change->{type} eq 'update')
                    {
                        push @{ $update{$change->{table_name}} }, $change;
                    }
                    elsif ($change->{type} eq 'delete')
                    {
                        push @{ $delete{$change->{table_name}} }, $change;
                    }
                    else
                    {
                        print "UNKNOWN COMMAND TYPE $change->{type} $change->{sql}\n";
                    }
                }
            }
        }
    }

    # Determine which tables require a lock;

    my %tables_requiring_lock;
    for my $table_name (keys %all_tables) {
        my $table_object = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self) ||
                           UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => 'UR::DataSource::Meta');
        if (my @bitmap_index_names = $table_object->bitmap_index_names) {
            my $changes;
            if ($changes = $insert{$table_name} or $changes = $delete{$table_name}) {
                $tables_requiring_lock{$table_name} = 1;
            }
            elsif (not $tables_requiring_lock{$table_name}) {
                $changes = $update{$table_name};
                my @column_names = sort map { @{ $_->{column_names} } } @$changes;
                my $last_column_name = "";
                for my $column_name (@column_names) {
                    next if $column_name eq $last_column_name;
                    my $column_obj = UR::DataSource::RDBMS::TableColumn->get(
                                                   data_source => $table_object->data_source,
                                                   table_name => $table_name,
                                                   column_name => $column_name,
                                               );
                    if ($column_obj->bitmap_index_names) {
                        $tables_requiring_lock{$table_name} = 1;
                        last;
                    }
                    $last_column_name = $column_name;
                }
            }
        }
    }

    #
    # Make a mapping of prerequisites for each command,
    # and a reverse mapping of dependants for each command.
    #

    my %all_table_commands;
    my %prerequisites;
    my %dependants;

    for my $table_name (keys %all_tables) {
        my $table = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self) ||
                    UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => 'UR::DataSource::Meta');
        
        my @fk = $table->fk_constraints;

        if ($insert{$table_name})
        {
            $all_table_commands{"insert $table_name"} = 1;
        }

        if ($update{$table_name})
        {
            $all_table_commands{"update $table_name"} = 1;
        }

        if ($delete{$table_name})
        {
            $all_table_commands{"delete $table_name"} = 1;
        }

        # Go through the constraints.
        for my $fk (@fk)
        {
            my $r_table_name = $fk->r_table_name;
            my $r_table = UR::DataSource::RDBMS::Table->get(table_name => $r_table_name, data_source => $self) ||
                          UR::DataSource::RDBMS::Table->get(table_name => $r_table_name, data_source => 'UR::DataSource::Meta');
            
            # RULES:
            # insert r_table_name       before insert table_name
            # insert r_table_name       before update table_name
            # delete table_name         before delete r_table_name
            # update table_name         before delete r_table_name

            if ($insert{$table_name} and $insert{$r_table_name})
            {
                $prerequisites{"insert $table_name"}{"insert $r_table_name"} = $fk;
                $dependants{"insert $r_table_name"}{"insert $table_name"} = $fk;
            }

            if ($update{$table_name} and $insert{$r_table_name})
            {
                $prerequisites{"update $table_name"}{"insert $r_table_name"} = $fk;
                $dependants{"insert $r_table_name"}{"update $table_name"} = $fk;
            }

            if ($delete{$r_table_name} and $delete{$table_name})
            {
                $prerequisites{"delete $r_table_name"}{"delete $table_name"} = $fk;
                $dependants{"delete $table_name"}{"delete $r_table_name"} = $fk;
            }

            if ($delete{$r_table_name} and $update{$table_name})
            {
                $prerequisites{"delete $r_table_name"}{"update $table_name"} = $fk;
                $dependants{"update $table_name"}{"delete $r_table_name"} = $fk;
            }
        }
    }

    #
    # Use the above mapping to build an ordered list of general commands.
    # Note that the general command is something like "insert EMPLOYEES",
    # while the explicit command is an exact insert statement with params.
    #

    my @general_commands_in_order;
    my %self_referencing_table_commands;

    my %all_unresolved = %all_table_commands;
    my $unresolved_count;
    my $last_unresolved_count = 0;
    my @ready_to_add = ();

    while ($unresolved_count = scalar(keys(%all_unresolved)))
    {
        if ($unresolved_count == $last_unresolved_count)
        {
            # We accomplished nothing on the last iteration.
            # We are in an infinite loop unless something is done.
            # Rather than die with an error, issue a warning and attempt to
            # brute-force the sync.

            # Process something with minimal deps as a work-around.
            my @ordered_by_least_number_of_prerequisites =
                sort{ scalar(keys(%{$prerequisites{$a}})) <=>  scalar(keys(%{$prerequisites{$b}})) }
                grep { $prerequisites{$_} }
                keys %all_unresolved;

            @ready_to_add = ($ordered_by_least_number_of_prerequisites[0]);
            warn "Circular dependency! Pushing @ready_to_add to brute-force the save.\n";
            print STDERR Dumper(\%objects_by_class_name, \%prerequisites, \%dependants) . "\n";
        }
        else
        {
            # This is the normal case.  It is either the first iteration,
            # or we are on additional iterations with some progress made
            # in the last iteration.

            # Find commands which have no unresolved prerequisites.
            @ready_to_add =
                grep { not $prerequisites{$_} }
                keys %all_unresolved;

            # If there are none of the above, find commands
            # with only self-referencing prerequisites.
            unless (@ready_to_add)
            {
                # Find commands with only circular dependancies.
                @ready_to_add =

                    # The circular prerequisite must be the only prerequisite on the table.
                    grep { scalar(keys(%{$prerequisites{$_}})) == 1 }

                    # The prerequisite must be the same as the the table itself.
                    grep { $prerequisites{$_}{$_} }

                    # There must be prerequisites for the given table,
                    grep { $prerequisites{$_} }

                    # Look at all of the unresolved table commands.
                    keys %all_unresolved;

                # Note this for below.
                # It records the $fk object which is circular.
                for my $table_command (@ready_to_add)
                {
                    $self_referencing_table_commands{$table_command} = $prerequisites{$table_command}{$table_command};
                }
            }
        }

        # Record our current unresolved count for comparison on the next iteration.
        $last_unresolved_count = $unresolved_count;

        for my $db_command (@ready_to_add)
        {
            # Put it in the list.
            push @general_commands_in_order, $db_command;

            # Delete it from the main hash of command/table pairs
            # for which dependencies are not resolved.
            delete $all_unresolved{$db_command};

            # Find anything which depended on this command occurring first
            # and remove this command from that command's prerequisite list.
            for my $dependant (keys %{ $dependants{$db_command} })
            {
                # Tell it to take us out of its list of prerequisites.
                delete $prerequisites{$dependant}{$db_command} if $prerequisites{$dependant};

                # Get rid of the prereq entry if it is empty;
                delete $prerequisites{$dependant} if (keys(%{ $prerequisites{$dependant} }) == 0);
            }

            # Note that nothing depends on this command any more since it has been queued.
            delete $dependants{$db_command};
        }
    }

    # Go through the ordered list of general commands (ie "insert TABLE_NAME")
    # and build the list of explicit commands.
    my @explicit_commands_in_order;
    for my $general_command (@general_commands_in_order)
    {
        my ($dml_type,$table_name) = split(/\s+/,$general_command);


        if (my $circular_fk = $self_referencing_table_commands{$general_command})
        {
            # A circular foreign key requires that the
            # items be inserted in a specific order.
            my (@rcol) = $circular_fk->column_names;

            # Get the IDs and objects which need to be saved.
            my @cmds = @{ $explicit_commands_by_type_and_table{$dml_type}{$table_name} };
            my @ids =  map { $_->{id} } @cmds;

#            my @objs = $cmds[0]->{class}->is_loaded(\@ids);
            my $is_loaded_class = ($dml_type eq 'delete')
                ? $cmds[0]->{class}->ghost_class
                : $cmds[0]->{class};

            my @objs = $is_loaded_class->is_loaded(\@ids);
            my %objs = map { $_->id => $_ } @objs;

            # Produce the explicit command list in dep order.
            my %unsorted_cmds = map { $_->{id} => $_ } @cmds;
            my $add;
            my @local_explicit_commands;
            $add = sub {
                my ($cmd) = @_;
                my $obj = $objs{$cmd->{id}};
                my $pid = $obj->class->composite_id(map { $obj->$_ } @rcol);
                if (defined $pid) {   # This recursive foreign key dep may have been optional
                    my $pcmd = delete $unsorted_cmds{$pid};
                    $add->($pcmd) if $pcmd;
                }
                push @local_explicit_commands, $cmd;
            };
            for my $cmd (@cmds) {
                next unless $unsorted_cmds{$cmd->{id}};
                $add->(delete $unsorted_cmds{$cmd->{id}});
            }

            if ($dml_type eq 'delete') {
                @local_explicit_commands =
                    reverse @local_explicit_commands;
            }

            push @explicit_commands_in_order, @local_explicit_commands;
        }
        else
        {
            # Order is irrelevant on non-self-referencing tables.
            push @explicit_commands_in_order, @{ $explicit_commands_by_type_and_table{$dml_type}{$table_name} };
        }
    }

    my %table_objects_by_class_name;
    my %column_objects_by_class_and_column_name;

    # Make statement handles.
    my %sth;
    for my $cmd (@explicit_commands_in_order)
    {
        my $sql = $cmd->{sql};

        unless ($sth{$sql})
        {
            my $class_name = $cmd->{class};

            # get the db handle to use for this class
            my $dbh = $cmd->{'dbh'};   #$class_name->dbh;
            my $sth = $dbh->prepare($sql);
            $sth{$sql} = $sth;

            if ($dbh->errstr)
            {
                $self->error_message("Error preparing SQL:\n$sql\n" . $dbh->errstr . "\n");
                return;
            }
            
            my $tables = $table_objects_by_class_name{$class_name};
            my $class_object = $class_name->get_class_object;
            unless ($tables) {                
                my $tables;
                my @all_table_names = $class_object->all_table_names;                
                for my $table_name (@all_table_names) {                    
                    my $table = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self) ||
                                UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => 'UR::DataSource::Meta');
                    push @$tables, $table;
                    $column_objects_by_class_and_column_name{$class_name} ||= {};             
                    my $columns = $column_objects_by_class_and_column_name{$class_name};
                    unless (%$columns) {
                        for my $column ($table->columns) {
                            $columns->{$column->column_name} = $column;
                        }
                    }
                }
                $table_objects_by_class_name{$class_name} = $tables;
            }

            my @column_objects = 
                map {
                    my $column = $column_objects_by_class_and_column_name{$class_name}{$_};
                    unless ($column) {
                        print "looking at parent classes for $class_name\n";
			for my $ancestor_class_name ($class_object->ordered_inherited_class_names) {
	                    $column = $column_objects_by_class_and_column_name{$ancestor_class_name}{$_};
                            if ($column) {
		                $column_objects_by_class_and_column_name{$class_name}{$_} = $column;
        	                last;
                            }
			}
                        unless ($column) {
                            $DB::single = 1;
                            die "Failed to find a column object column $_ for class $class_name";
                        }
                    }
                    $column;
                }
                @{ $cmd->{column_names} };

            # print "Column Types: @column_types\n";

            for my $n (0 .. $#column_objects) {
                if ($column_objects[$n]->data_type eq 'BLOB')
                {
                    $sth->bind_param($n+1, undef, { ora_type => 113,  ora_field => $column_objects[$n]->column_name });
                }
            }
        }
    }

    # Set a savepoint if possible.
    my $savepoint;
    if ($self->can_savepoint) {
        $savepoint = $self->_last_savepoint;
        if ($savepoint) {
            $savepoint++;
        }
        else {
            $savepoint=1;
        }
        my $sp_name = "sp".$savepoint;
        unless ($self->set_savepoint($sp_name)) {
            $self->error_message("Failed to set a savepoint on "
                . $self->class
                . ": "
                . $dbh->errstr
            );
            return;
        }
        $self->_last_savepoint($savepoint);
    }
    else {
        # FIXME SQLite dosen't support savepoints, but autocommit is already off so this dies?!
        #$dbh->begin_work;
    }

    # Do any explicit table locking necessary.
    if (my @tables_requiring_lock = sort keys %tables_requiring_lock) {
        $self->debug_message("Locking tables: @tables_requiring_lock.");
        my $max_failed_attempts = 10;
        for my $table_name (@tables_requiring_lock) {
            my $table = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self) ||
                        UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => 'UR::DataSource::Meta');
            my $dbh = $table->dbh;
            my $sth = $dbh->prepare("lock table $table_name in exclusive mode");
            my $failed_attempts = 0;
            my @err;
            for (1) {
                unless ($sth->execute) {
                    $failed_attempts++;
                    $self->warning_message(
                        "Failed to lock $table_name (attempt # $failed_attempts): "
                        . $sth->errstr
                    );
                    push @err, $sth->errstr;
                    unless ($failed_attempts >= $max_failed_attempts) {
                        redo;
                    }
                }
            }
            if ($failed_attempts > 1) {
                my $err = join("\n",@err);
                $UR::Context::current->send_email(
                    To => 'autobulk@watson.wustl.edu',
                    From => App->prog_name . ' <autobulk@watson.wustl.edu>',
                    Subject => (
                            $failed_attempts >= $max_failed_attempts
                            ? "sync_database lock failure after $failed_attempts attempts"
                            : "sync_database lock success after $failed_attempts attempts"
                        )
                        . " in " . App->prog_name
                        . " on $table_name",
                    Message => qq/
                        $failed_attempts attempts to lock table $table_name

                        Errors:
                        $err

                        The complete table lock list for this sync:
                        @tables_requiring_lock
                    /
                );
                if ($failed_attempts >= $max_failed_attempts) {
                    $self->error_message(
                        "Could not obtain an exclusive table lock on table "
                        . $table_name . " after $failed_attempts attempts"
                    );
                    $self->rollback_to_savepoint($savepoint);
                    return;
                }
            }
        }
    }

    # Execute the commands in the correct order.

    my @failures;
    my $last_failure_count = 0;
    my @previous_failure_sets;

    # If there are failures, we fall-back to brute force and send
    # a message to support to debug the inefficiency.
    my $skip_fault_tolerance_check = 1;

    for (1) {
        @failures = ();
        for my $cmd (@explicit_commands_in_order) {
            unless ($sth{$cmd->{sql}}->execute(@{$cmd->{params}}))
            {
                my $dbh = $cmd->{class}->dbh;
                push @failures, {cmd => $cmd, error_message => $dbh->errstr};
                last if $skip_fault_tolerance_check;
            }
            $sth{$cmd->{sql}}->finish();
        }

        if (@failures) {
            # There have been some failures.  In case the error has to do with
            # a failure to correctly determine dependencies in the code above,
            # we will retry the set of failed commands.  This repeats as long
            # as some progress is made on each iteration.
            if ( (@failures == $last_failure_count) or $skip_fault_tolerance_check) {
                # We've tried this exact set of comands before and failed.
                # This is a real error.  Stop retrying and report.
                for my $error (@failures)
                {
                    $self->error_message("Error executing SQL:\n$error->{cmd}{sql}\n" . $error->{error_message} . "\n");
                }
                last;
            }
            else {
                # We've failed, but we haven't retried this exact set of commands
                # and found the exact same failures.  This is either the first failure,
                # or we had failures before and had success on the last brute-force
                # approach to sorting commands.  Try again.
                push @previous_failure_sets, \@failures;
                @explicit_commands_in_order = map { $_->{cmd} } @failures;
                $last_failure_count = scalar(@failures);
                $self->warning_message("RETRYING SAVE");
                redo;
            }
        }
    }

    # Rollback to savepoint if there are errors.
    if (@failures) {
        if ($savepoint eq "NONE") {
            # A failure on a database which does not support savepoints.
            # We must rollback the entire transacation.
            # This is only a problem for a mixed raw-sql and UR::Object environment.
            $dbh->rollback;
        }
        else {
            $self->_reverse_sync_database();
        }
        # Return false, indicating failure.
        return;
    }

    unless ($self->_set_specified_objects_saved_uncommitted($changed_objects)) {
        Carp::confess("Error setting objects to a saved state after sync_database.  Exiting.");
        return;
    }
    
    if (exists $params{'commit_on_success'} and ($params{'commit_on_success'} eq '1')) {
        # Commit the current transaction.
        # The handles will automatically update their objects to 
        # a committed state from the one set above.
        # It will throw an exception on failure.
        $dbh->commit;
    }

    # Though we succeeded, see if we had to use the fault-tolerance code to
    # do so, and warn software support.  This should never occur.
    if (@previous_failure_sets) {
        my $msg = "Dependency failure saving: " . Dumper(\@explicit_commands_in_order)
                . "\n\nThe following error sets were produced:\n"
                . Dumper(\@previous_failure_sets) . "\n\n" . Carp::cluck . "\n\n";

        $self->warning_message($msg);
        $UR::Context::current->send_email(
            To => UR::Context::Process->support_email,
            Subject => 'sync_database dependency sort failure',
            Message => $msg
        ) or $self->warning_message("Failed to send error email!");
    }

    return 1;
}

sub _reverse_sync_database {
    my $self = shift;

    unless ($self->can_savepoint) {
        # This will not respect manual DML
        # Developers must not use this back door on non-savepoint databases.
        $self->get_default_dbh->rollback;
        return "NONE";
    }

    my $savepoint = $self->_last_savepoint;
    unless ($savepoint) {
        Carp::confess("No savepoint set!");
    }

    my $sp_name = "sp".$savepoint;
    unless ($self->rollback_to_savepoint($sp_name)) {
        $self->error_message("Error removing savepoint $savepoint " . $self->get_default_dbh->errstr);
        return 1;
    }

    $self->_last_savepoint(undef);
    return $savepoint;
}


# Given a table object and a list of primary key values, return
# a where clause to match a row.  Some values may be undef (NULL)
# and it properly writes "column IS NULL".  As a side effect, the 
# @$values list is altered to remove the undef value
sub _matching_where_clause {
    my($self,$table_obj,$values) = @_;

    unless ($table_obj) {
        Carp::confess("No table passed to _matching_where_clause for $self!");
    }

    my @pks = $table_obj->primary_key_constraint_column_names;

    my @where;
    # in @$values, the updated data values always seem to be before the where clause
    # values but still in the right order, so start at the right place
    my $skip = scalar(@$values) - scalar(@pks);
    for (my($pk_idx,$values_idx) = (0,$skip); $pk_idx < @pks;) {
        if (defined $values->[$values_idx]) {
            push(@where, $pks[$pk_idx] . ' = ?');
            $pk_idx++; 
            $values_idx++;
        } else {
            push(@where, $pks[$pk_idx] . ' IS NULL');
            splice(@$values, $values_idx, 1);
            $pk_idx++;
        }
    }

    return join(' and ', @where);
}
            

sub _default_save_sql_for_object {
    my $self = shift;        
    my $object_to_save = shift;
    my %params = @_;
    
    my ($class,$id) = ($object_to_save->class, $object_to_save->id);
    
    # This was in some of the UR::Object::* meta-data stuff.
    # Reason unknown.
    #my $self = shift;
    #my $class_obj = UR::Object::Type->get(type_name => $self->type_name);
    #if ($class_obj and $class_obj->table_name) {
    #    return $self->SUPER::default_save_sql(@_);
    #}
    #else {
    #    return;
    #}
    
    my $class_object = $object_to_save->get_class_object;
    
    # This object may have uncommitted changes already saved.  
    # If so, work from the last saved data.
    # Normally, we go with the last committed data.
    
    my $compare_version = ($object_to_save->{'db_saved_uncommitted'} ? 'db_saved_uncommitted' : 'db_committed');

    # Determine what the overall save action for the object is,
    # and get a specific change summary if we're doing an update.
    
    my ($action,$change_summary);
    if ($object_to_save->isa('UR::Entity::Ghost'))
    {
        $action = 'delete';
    }                    
    elsif ($object_to_save->{$compare_version})
    {
        $action = 'update';
        $change_summary = $object_to_save->property_diff($object_to_save->{$compare_version});         
    }
    else
    {
        $action = 'insert';
    }
    
    # Handle each table.  There is usually only one, unless,
    # there is inheritance within the schema.
    my @save_table_names = 
        map  { uc }
        grep { $_ }
        $class_object->all_table_names;
        
    @save_table_names = reverse @save_table_names unless ($object_to_save->isa('UR::Entity::Ghost'));

    my @commands;
    for my $table_name (@save_table_names)
    {
        # Get general info on the table we're working-with.                
        
        my $dsn = ref($self) ? $self->id : $self;  # The data source name
        
        my $table = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $dsn) ||
                    UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => 'UR::DataSource::Meta');
        unless ($table) {
            Carp::confess("No table $table_name found for data source $dsn!");
        }        
        my @table_class_obj = grep { $_->class_name !~ /::Ghost$/ } UR::Object::Type->is_loaded(table_name => $table_name);
        my $table_class;
        my $table_class_obj;
        if (@table_class_obj == 1) {
            $table_class_obj = $table_class_obj[0]; 
            $table_class = $table_class_obj->class_name; 
        }
        else {
            Carp::confess("NO CLASS FOR $table_name: @table_class_obj!\n");
        }        
        my $table_name_to_update = $table_name;
       
         
        my $data_source = $UR::Context::current->resolve_data_source_for_object($object_to_save);
        unless ($data_source) {
            Carp::confess("No ds on $object_to_save!");
        }
        my $db_owner = $data_source->owner;
    
        # The "action" now can vary on a per-table basis.
       
        my $table_action = $action;
       
        # Handle re-classification of objects.
        # We skip deletion and turn insert into update in these cases.
        
        if ( ($table_class ne $class) and ( ($table_class . "::Ghost") ne $class) ) {
            if ($action eq 'delete') {
                # see if the object we're deleting actually exists reclassified
                my $replacement = $table_class->is_loaded($id);
                if ($replacement) {
                    next;
                }
            }
            elsif ($action eq 'insert') {
                # see if the object we're inserting is actually a reclassification
                # of a pre-existing object
                my $replacing = $table_class->ghost_class->is_loaded($id);
                if ($replacing) {
                    $table_action = 'update';
                    $change_summary = $object_to_save->property_diff(%$replacing);
                }
            }
        }
        
        # Determine the $sql and @values needed to save this object.
        
        my ($sql, @changed_cols, @values, @value_properties, %value_properties);
        
        if ($table_action eq 'delete')
        {
            # A row loaded from the database with its object deleted.
            # Delete the row in the database.
            
            @values = $object_to_save->decomposed_id($id);
            my $where = $self->_matching_where_clause($table, \@values);

            $sql = " DELETE FROM ";
            $sql .= "${db_owner}." if ($db_owner);
            $sql .= "$table_name_to_update WHERE $where";

            push @commands, { type => 'delete', table_name => $table_name, column_names => undef, sql => $sql, params => \@values, class => $table_class, id => $id, dbh => $data_source->get_default_dbh };
        }                    
        elsif ($table_action eq 'update')
        {
            # Pre-existing row.  
            # Update in the database if there are columns which have changed.

            my $changes_for_this_table;
            if (@save_table_names > 1)
            {
                my @changes = 
                    map { $_ => $change_summary->{$_} }
                    grep { $class_object->table_for_property($_) eq $table_name }
                    keys %$change_summary;
                $changes_for_this_table = {@changes};
            }
            else
            {
                # Shortcut and use the overall changes summary when
                # there is only one table.
                $changes_for_this_table = $change_summary;
            }
            
            for my $property (keys %$changes_for_this_table)
            {
                my $column_name = $class_object->column_for_property($property); 
                Carp::confess("No column in table $table_name for property $property?") unless $column_name;
                push @changed_cols, $column_name;
                push @values, $changes_for_this_table->{$property};
            }
            
            $object_to_save->debug_message("Changed cols: @changed_cols", 4);
            
            if (@changed_cols)
            {
                @values = ( (map { $object_to_save->$_ } @changed_cols) , $object_to_save->decomposed_id($id));
                my $where = $self->_matching_where_clause($table, \@values);

                $sql = " UPDATE ";
                $sql .= "${db_owner}." if ($db_owner);
                $sql .= "$table_name_to_update SET " . join(",", map { "$_ = ?" } @changed_cols) . " WHERE $where";

                push @commands, { type => 'update', table_name => $table_name, column_names => \@changed_cols, sql => $sql, params => \@values, class => $table_class, id => $id, dbh => $data_source->get_default_dbh };
            }
        }
        elsif ($table_action eq 'insert')
        {
            # An object without a row in the database.
            # Insert into the database.
            
            my @changed_cols = reverse sort $table->column_names; 
            
            $sql = " INSERT INTO ";
            $sql .= "${db_owner}." if ($db_owner);
            $sql .= "$table_name_to_update (" 
                    . join(",", @changed_cols) 
                    . ") VALUES (" 
                    . join(',', split(//,'?' x scalar(@changed_cols))) . ")";
            
            @values = map { $object_to_save->$_ } (@changed_cols);                     
            push @commands, { type => 'insert', table_name => $table_name, column_names => \@changed_cols, sql => $sql, params => \@values, class => $table_class, id => $id, dbh => $data_source->get_default_dbh };
        }
        else
        {
            die "Unknown action $table_action for $object_to_save" . Dumper($object_to_save) . "\n";
        }
        
    } # next table 
    
    return @commands;
}

sub _set_specified_objects_saved_uncommitted {
    my ($self,$objects_arrayref) = @_;
    # Sets an objects as though the has been saved but tha changes have not been committed.
    # This is called automatically by _sync_databases.
    
    my %objects_by_class;
    my $class_name;
    for my $object (@$objects_arrayref) {
        $class_name = ref($object);
        $objects_by_class{$class_name} ||= [];
        push @{ $objects_by_class{$class_name} }, $object;
    }
    
    for my $class_name (sort keys %objects_by_class) {
        my $class_object = $class_name->get_class_object;
        my @property_names = 
            map { $_->property_name }
            grep { $_->column_name }
            $class_object->get_all_property_objects;
        
        for my $object (@{ $objects_by_class{$class_name} }) {
            $object->{db_saved_uncommitted} ||= {};
            my $db_saved_uncommitted = $object->{db_saved_uncommitted};            
            for my $property ( @property_names ) {
                $db_saved_uncommitted->{$property} = $object->$property;
            }
        }
    }
    return 1;            
}


sub _get_current_entities {
    my $self = shift;
    my @class_meta = UR::Object::Type->is_loaded(
        data_source => $self->id
    );
    my @objects;
    for my $class_meta (@class_meta) {
        next unless $class_meta->generated();  # Ungenerated classes won't have any instances
        my $class_name = $class_meta->class_name;
        push @objects, $class_name->all_objects_loaded();
    }
    return @objects;
}


sub _set_all_objects_saved_committed {
    # called by UR::DBI on commit
    my $self = shift;
    my @objects = $self->_get_current_entities;        
    for my $obj (@objects)  {
        unless ($self->_set_object_saved_committed($obj)) {
            die "An error occurred setting " . $obj->display_name_full 
             . " to match the committed database state.  Exiting...";
        }
    }
}

sub _set_object_saved_committed {
    # called by the above, and some test cases
    my ($self, $object) = @_;
    if ($object->{db_saved_uncommitted}) {
        if ($object->isa("UR::Object::Ghost")) {
            $object->signal_change("commit");
            $object->delete_object;
        }
        else {
            %{ $object->{db_committed} } = (
                ($object->{db_committed} ? %{ $object->{db_committed} } : ()),
                %{ $object->{db_saved_uncommitted} }
            );
            delete $object->{db_saved_uncommitted};
            $object->signal_change("commit");
        }
    }
    return $object;
}

sub _set_all_objects_saved_rolled_back {
    # called by UR::DBI on commit
    my $self = shift;
    my @objects = $self->_get_current_entities;        
    for my $obj (@objects)  {
        unless ($self->_set_object_saved_rolled_back($obj)) {
            die "An error occurred setting " . $obj->display_name_full 
             . " to match the rolled-back database state.  Exiting...";
        }
    }
}

sub _set_object_saved_rolled_back {
    # called by the above, and some test cases    
    my ($self,$object) = @_;
    delete $object->{db_saved_uncommitted};
    return $object;
}


sub _do_on_default_dbh {
    my $self = shift;
    my $method = shift;

    return 1 unless $self->has_default_dbh();

    my $dbh = $self->get_default_dbh;
    unless ($dbh->$method(@_)) {
        $self->error_message("DataSource ",$self->get_name," failed to $method: ",$dbh->errstr);
        return undef;
    }

    return 1;
}

sub commit {
    my $self = shift;
    $self->_do_on_default_dbh('commit', @_);
}

sub rollback {
    my $self = shift;
    $self->_do_on_default_dbh('rollback', @_);
}

sub disconnect {
    my $self = shift;
    $self->_do_on_default_dbh('disconnect', @_);
}


sub resolve_dbic_schema_name {
    my $self = shift;

    my @schema_parts = split(/::/, ref($self) ? $self->class_name : $self);
    # This will be something like namespace::DataSource::name, change it to namespace::DBIC::name
    $schema_parts[1] = 'DBIC';
    my $schema_name = join('::',@schema_parts);

    return $schema_name;
}


sub get_dbic_schema {
    my $self = shift;

    my $schema_name = $self->resolve_dbic_schema_name();

    eval "use $schema_name;";
    die $@ if $@;

#    require DBIx::Class::Schema;
#
#    my $schema_isa = $schema_name . '::ISA';
#    { no strict 'refs';
#      @$schema_isa = ('DBIx::Class::Schema');
#    }
#
#    $schema_name->load_classes();

    return $schema_name->connect($self->_dbi_connect_args);
}


    


1;
