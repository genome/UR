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
    return unless($ds_name);
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

    $self->signal_change("connect");
    
    return $dbh;
}

sub _init_created_dbh {
    # override in sub-classes
    1;
}

# The default is to ignore no tables, but derived classes
# will probably override this
sub _ignore_table {
    0;
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


# A wrapper for DBI's table_info() since the DBD implementations of them
# aren't always exactly what we need in other places in the system.  Other
# subclasses can override it to get custom behavior
sub get_table_details_from_data_dictionary {
    return shift->_get_whatever_details_from_data_dictionary('table_info',@_);
}

sub _get_whatever_details_from_data_dictionary {
    my $self = shift;
    my $method = shift;

    my $dbh = $self->get_default_dbh();
    return unless $dbh;

    return $dbh->$method(@_);
}

sub get_column_details_from_data_dictionary {
    return shift->_get_whatever_details_from_data_dictionary('column_info',@_);
}

sub get_foreign_key_details_from_data_dictionary {
    return shift->_get_whatever_details_from_data_dictionary('foreign_key_info',@_);
}

sub get_primary_key_details_from_data_dictionary {
    return shift->_get_whatever_details_from_data_dictionary('primary_key_info',@_);
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
#
# FIXME The API for bitmap_index and unique_index methods here aren't the same as
# the other data_dictionary methods.  These tqo return hashrefs of massaged
# data while the others return DBI statement handles.
sub get_bitmap_index_details_from_data_dictionary {
    my $class = shift;
    Carp::confess("Class $class didn't define its own bitmap_index_info() method");
}


# Derived classes should define a method to return a ref to a hash keyed by constraint
# names.  Each value holds a listref of hashrefs containing these keys:
# CONSTRAINT_NAME and COLUMN_NAME
sub get_unique_index_details_from_data_dictionary {
    my $class = shift;
    Carp::confess("Class $class didn't define its own unique_index_info() method");
}

sub autogenerate_new_object_id_for_class_name_and_rule {
    # The sequences in the database are named by a naming convention which allows us to connect them to the table
    # whose surrogate keys they fill.  Look up the sequence and get a unique value from it for the object.
    # If and when we save, we should not get any integrity constraint violation errors.

    my $self = shift;
    my $class_name = shift;
    my $rule = shift;  # Not used for the moment...

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

    # FIXME Each class should have a way to override what sequence generator to use
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
    $sql .= "\n$where_clause" if defined($where_clause) and length($where_clause);
    $sql .= "\n$connect_by_clause" if $connect_by_clause;           
    $sql .= "\n$order_by_clause"; 

    my $dbh = $self->get_default_dbh;    
    my $sth = $dbh->prepare($sql,$query_config);
    unless ($sth) {
        $class->error_message("Failed to prepare SQL $sql\n" . $dbh->errstr . "\n");
        Carp::confess($class->error_message);
    }    
    unless ($sth->execute(@all_sql_params)) {
        $class->error_message("Failed to execute SQL $sql\n" . $sth->errstr . "\n" . Data::Dumper::Dumper(\@$sql_params) . "\n");
        Carp::confess($class->error_message);
    }    

    die unless $sth;    

    $self->signal_change('query',$sql);

    # buffers for the iterator
    my $next_db_row;
    my $pending_db_object_data;
    
    my $ur_test_filldb = $ENV{'UR_TEST_FILLDB'};
    
    my $iterator = sub {
    
        $next_db_row = $sth->fetchrow_arrayref;
        #$self->signal_change('fetch',$next_db_row);  # FIXME: commented out because it may make fetches too slow
        
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
        $self->_CopyToAlternateDB($class,$dbh,$next_db_row) if $ur_test_filldb;
        
        return $next_db_row;
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
        my $cid = $class_name->_resolve_composite_id(@id_vals);
        push @id_fetch_set, $cid;       
    }
    
    return @id_fetch_set;
}


sub _sync_database {
    my $self = shift;
    my %params = @_;
    
    unless (ref($self)) {
        if ($self->isa("UR::Singleton")) {
            $self = $self->_singleton_object;
        }
        else {
            die "Called as a class-method on a non-singleton datasource!";
        }
    }
    
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
                    my $table = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self->class) ||
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
        my $table_object = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self->class) ||
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
        my $table = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self->class) ||
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
        my $tmparray;
        for my $fk (@fk)
        {
            my $r_table_name = $fk->r_table_name;
            my $r_table = UR::DataSource::RDBMS::Table->get(table_name => $r_table_name, data_source => $self->class) ||
                          UR::DataSource::RDBMS::Table->get(table_name => $r_table_name, data_source => 'UR::DataSource::Meta');
            
            # RULES:
            # insert r_table_name       before insert table_name
            # insert r_table_name       before update table_name
            # delete table_name         before delete r_table_name
            # update table_name         before delete r_table_name

            if ($insert{$table_name} and $insert{$r_table_name})
            {
                $tmparray = $prerequisites{"insert $table_name"}{"insert $r_table_name"} ||= [];
                push @$tmparray, $fk;

                $tmparray = $dependants{"insert $r_table_name"}{"insert $table_name"} ||= [];
                push @$tmparray, $fk;
            }

            if ($update{$table_name} and $insert{$r_table_name})
            {
                $tmparray = $prerequisites{"update $table_name"}{"insert $r_table_name"} ||= [];
                push @$tmparray, $fk;

                $tmparray = $dependants{"insert $r_table_name"}{"update $table_name"} ||= [];
                push @$tmparray, $fk;
            }

            if ($delete{$r_table_name} and $delete{$table_name})
            {
                $tmparray = $prerequisites{"delete $r_table_name"}{"delete $table_name"} ||= [];
                push @$tmparray, $fk;

                $tmparray = $dependants{"delete $table_name"}{"delete $r_table_name"} ||= [];
                push @$tmparray, $fk;
            }

            if ($delete{$r_table_name} and $update{$table_name})
            {
                $tmparray = $prerequisites{"delete $r_table_name"}{"update $table_name"} ||= [];
                push @$tmparray, $fk;
                
                $tmparray = $dependants{"update $table_name"}{"delete $r_table_name"} ||= [];
                push @$tmparray, $fk;
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


        if (my $circular_fk_list = $self_referencing_table_commands{$general_command})
        {
            # A circular foreign key requires that the
            # items be inserted in a specific order.
            my (@rcol_sets) = 
                map { [ $_->column_names ] } 
                @$circular_fk_list;

            # Get the IDs and objects which need to be saved.
            my @cmds = @{ $explicit_commands_by_type_and_table{$dml_type}{$table_name} };
            my @ids =  map { $_->{id} } @cmds;

            # my @objs = $cmds[0]->{class}->is_loaded(\@ids);
            my $is_loaded_class = ($dml_type eq 'delete')
                ? $cmds[0]->{class}->ghost_class
                : $cmds[0]->{class};

            my @objs = $is_loaded_class->is_loaded(\@ids);
            my %objs = map { $_->id => $_ } @objs;

            # Produce the explicit command list in dep order.
            my %unsorted_cmds = map { $_->{id} => $_ } @cmds;
            my $add;
            my @local_explicit_commands;
            my %adding;
            $add = sub {
                my ($cmd) = @_;
                if ($adding{$cmd}) {
                    $DB::single = 1;
                    Carp::confess("Circular foreign key!") unless $main::skip_croak;
                }
                $adding{$cmd} = 1;
                my $obj = $objs{$cmd->{id}};
                for my $rcol_set (@rcol_sets) {
                    my $pid = $obj->class->_resolve_composite_id(map { $obj->$_ } @$rcol_set);
                    if (defined $pid) {   # This recursive foreign key dep may have been optional
                        my $pcmd = delete $unsorted_cmds{$pid};
                        $add->($pcmd) if $pcmd;
                    }
                }
                delete $adding{$cmd};
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
                    my $table = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self->class) ||
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
            my $table = UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $self->class) ||
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
                #my $dbh = $cmd->{class}->dbh;
                my $dbh = UR::Context->resolve_data_source_for_object($cmd->{class})->get_default_dbh;
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
            
            #$object_to_save->debug_message("Changed cols: @changed_cols", 4);
            
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
            
            @values = map { 
                    # when there is a column but no property, use NULL as the value
                    $object_to_save->can($_) 
                        ? $object_to_save->$_ 
                        : undef
                } 
                (@changed_cols);
                
            push @commands, { type => 'insert', table_name => $table_name, column_names => \@changed_cols, sql => $sql, params => \@values, class => $table_class, id => $id, dbh => $data_source->get_default_dbh };
        }
        else
        {
            die "Unknown action $table_action for $object_to_save" . Dumper($object_to_save) . "\n";
        }
        
    } # next table 
    
    return @commands;
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

sub _generate_class_data_for_loading {
    my ($self, $class_meta) = @_;

    my $parent_class_data = $self->SUPER::_generate_class_data_for_loading($class_meta);

    my @class_hierarchy = ($class_meta->class_name,$class_meta->ordered_inherited_class_names);
    my $order_by_clause;
    do {
        my @id_column_names;    
        for my $inheritance_class_name (@class_hierarchy) {
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
    
    my @all_table_properties;
    my @direct_table_properties;
    my $first_table_name;
    my $sub_classification_method_name;
    my ($sub_classification_meta_class_name, $sub_classification_property_name);
    
    my @base_joins;
    my $prev_table_name;
    my $prev_id_column_name;
   
    for my $co ( $class_meta, @{ $parent_class_data->{parent_class_objects} } ) {   
        my $table_name = $co->table_name;
        next unless $table_name;
        
        $first_table_name ||= $co->table_name;
        $sub_classification_method_name ||= $co->sub_classification_method_name;
        $sub_classification_meta_class_name ||= $co->sub_classification_meta_class_name;
        $sub_classification_property_name   ||= $co->sub_classification_property_name;
        
        push @all_table_properties, 
            map { [$co, $_, $table_name, 0] }
            sort { $a->property_name cmp $b->property_name }
            grep { (defined $_->column_name && $_->column_name ne '') or
                   (defined $_->calculate_sql && $_->calculate_sql ne '') }
            UR::Object::Property->get( type_name => $co->type_name );

        @direct_table_properties = @all_table_properties if $class_meta eq $co;
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

    my $class_data = {
        %$parent_class_data,
        
        all_table_properties                => \@all_table_properties,
        direct_table_properties             => \@direct_table_properties,
        
        first_table_name                    => $first_table_name,
        sub_classification_method_name      => $sub_classification_method_name,
        sub_classification_meta_class_name  => $sub_classification_meta_class_name,
        sub_classification_property_name    => $sub_classification_property_name,
        
        base_joins                          => \@base_joins,   
        order_by_clause                     => $order_by_clause,
        
        lob_column_names                    => \@lob_column_names,
        lob_column_positions                => \@lob_column_positions,
        
        query_config                        => $query_config,
        post_process_results_callback       => $post_process_results_callback,
    };
    
    return $class_data;
}

sub _generate_template_data_for_loading {
    my ($self, $rule_template) = @_;
        
    # class-based values
    
    my $class_name = $rule_template->subject_class_name;
    my $class_meta = $class_name->get_class_object;

    my $class_data = $self->_get_class_data_for_loading($class_meta);       

    my @parent_class_objects                = @{ $class_data->{parent_class_objects} };
    my @all_table_properties                = @{ $class_data->{all_table_properties} };
    my $first_table_name                    = $class_data->{first_table_name};
    
    my @all_id_property_names               = @{ $class_data->{all_id_property_names} };
    my @id_properties                       = @{ $class_data->{id_properties} };   
    my $id_property_sorter                  = $class_data->{id_property_sorter};    
    
    my $order_by_clause                     = $class_data->{order_by_clause};
    
    my @lob_column_names                    = @{ $class_data->{lob_column_names} };
    my @lob_column_positions                = @{ $class_data->{lob_column_positions} };
    
    my $query_config                        = $class_data->{query_config}; 
    my $post_process_results_callback       = $class_data->{post_process_results_callback};

    my $class_table_name                    = $class_data->{class_table_name};
    
    # individual query/boolexpr based
    
    my $recursion_desc = $rule_template->recursion_desc;
    my $recurse_property_on_this_row;
    my $recurse_property_referencing_other_rows;
    if ($recursion_desc) {
        ($recurse_property_on_this_row,$recurse_property_referencing_other_rows) = @$recursion_desc;        
    }        
    
    # the following two sets of variables hold the net result of the logic
    my $select_clause;
    my $select_hint;
    my $from_clause;
    my $connect_by_clause;

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
    );
    
    for my $co ( $class_meta, @parent_class_objects ) {
        my $type_name  = $co->type_name;
        my $class_name = $co->class_name;
        my @id_property_objects = $co->get_id_property_objects;
        my %id_properties = map { $_->property_name => 1 } @id_property_objects;
        my @id_column_names =
            map { $_->column_name }
            @id_property_objects;
        my $table_name = $co->table_name;
        if ($table_name) {
            $first_table_name ||= $table_name;
            if ($prev_table_name) {
                die "Database-level inheritance cannot be used with multi-value-id classes ($class_name)!" if @id_property_objects > 1;
                push @sql_joins,
                    $table_name =>
                        {
                            $id_property_objects[0]->column_name => { 
                                link_table_name => $prev_table_name, 
                                link_column_name => $prev_id_column_name 
                            }
                        };
                # Not sure why this was here before we moved the logic around.
                # It seems that worst case on removing it is overly redundant queries.
                # The worst case on keeping it is leaving a filter out, which we don't want.
                #delete $filters{ $id_property_objects[0]->property_name } if $pk_used;
            }
            $prev_table_name = $table_name;
            $prev_id_column_name = $id_property_objects[0]->column_name;
        }

        for my $property_name (sort keys %filters) {                
            my $property = UR::Object::Property->get(type_name => $type_name, property_name => $property_name);                
            next unless $property;
            
            my $operator       = $rule_template->operator_for_property_name($property_name);
            my $value_position = $rule_template->value_position_for_property_name($property_name);
            
            delete $filters{$property_name};
            $pk_used = 1 if $id_properties{ $property_name };
            
            if ($property->can("expr_sql")) {
                unless ($table_name) {
                    $self->warning_message("Property '$property_name' of class '$class_name' can 'expr_sql' but has no table!");
                    next;
                }
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
                unless ($table_name) {
                    $self->warning_message("Property '$property_name' of class '$class_name'  has column '$column_name' but has no table!");
                    next;
                }
                # normal column: filter on it
                push @sql_filters, 
                    $table_name => 
                        { 
                            $column_name => { operator => $operator, value_position => $value_position }
                        };
            }
            elsif ($property->is_legacy_eav) {
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
                next;
            }
        }
    } # end of inheritance loop
        
    if ( my @errors = keys(%filters) ) { 
        my $class_name = $class_meta->class_name;
        $self->error_message("Unknown param(s) >@errors< used to generate SQL for $class_name!");
        Carp::confess();
    }

    my $last_class_name = $class_name;
    my $last_class_object = $class_meta;        
    my $last_table_alias = $last_class_object->table_name; 
    my $last_object_num = 0;
    my $alias_num = 1;

    my %joins_done;
    my @joins_done;


    DELEGATED_PROPERTY:
    for my $delegated_property (@delegated_properties) {
        my $last_alias_for_this_chain;
        my $alias_for_property_value;
    
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
        my $last_class_object_excluding_inherited_joins;
        
        my $final_join = $joins[-1];
        while (my $join = shift @joins) {
            #$DB::single = 1;
            #print "\tjoin $join\n";
            #        print Data::Dumper::Dumper($join);
            
            $join->{object_num} = 1 if not defined $join->{object_num};
            
            my $source_class_name = $join->{source_class};
            my $source_class_object = $join->{'source_class_meta'} || $source_class_name->get_class_object;                    

            my $foreign_class_name = $join->{foreign_class};
            my $foreign_class_object = $join->{'foreign_class_meta'} || $foreign_class_name->get_class_object;
            my($foreign_data_source) = UR::Context->resolve_data_sources_for_class_meta_and_rule($foreign_class_object, $rule_template);
            if ($foreign_data_source ne $self) {
                # FIXME - do something smarter in the future where it can do a join-y thing in memory
                $needs_further_boolexpr_evaluation_after_loading = 1;
                next DELEGATED_PROPERTY;
            }

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
                    $_->is_calculated ? (defined($_->calculate_sql) ? ($_->calculate_sql) : () ) : ($_->column_name)
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
            
            my $foreign_class_loading_data = $self->_get_class_data_for_loading($foreign_class_object);
            
            my $alias = $joins_done{$join->{id}};
            unless ($alias) {            
                $alias = "${relationship_name}_${alias_num}";
                $alias_num++;
                
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
                
                # Add all of the columns in the join table to the return list
                # Note that we increment the object numbers.
                push @all_table_properties, 
                    map { 
                        my $new = [@$_]; 
                        $new->[2] = $alias,
                        $new->[3]++; 
                        $new 
                    }
                    @{ $foreign_class_loading_data->{direct_table_properties} };                
            }

            $joins_done{$join->{id}} = $alias;
            push @joins_done, $join;
            
            # Set these for after all of the joins are done
            $last_class_name = $foreign_class_name;
            $last_class_object = $foreign_class_object;
            $last_alias_for_this_chain = $alias;
            $last_table_alias = $alias;
            $final_table_name_with_alias = "$foreign_table_name $alias";
            
            
            if ($join->{object_num} != $last_object_num) {
                $object_num++;
                $last_object_num = $join->{object_num};
                $last_class_object_excluding_inherited_joins = $last_class_object;
            }
            elsif (not defined $last_class_object_excluding_inherited_joins) {
                $last_class_object_excluding_inherited_joins = $last_class_object;
            }

            if (!@joins and not $alias_for_property_value) {
                if (grep { $_->[1]->property_name eq $final_accessor } @{ $foreign_class_loading_data->{direct_table_properties} }) {
                    $alias_for_property_value = $alias;
                    #print "found alias for $property_name on $foreign_class_name: $alias\n";
                }
                else {
                    #print "no alias for $property_name on $foreign_class_name\n";
                }
            }
            my @parents = grep { $_->table_name } $foreign_class_object->ordered_inherited_class_objects;   
            if (@parents) {
                #print "GOT PARENTS " . join(",", map { $_->class_name } @parents) . "\n";
                my @last_id_property_names = $foreign_class_object->id_property_names;
                for my $parent (@parents) {
                    my @parent_id_property_names = $parent->id_property_names;
                    die if @parent_id_property_names > 1;                    
                    unshift @joins, {
                        source_class => $last_class_name,
                        source_property_names => \@last_id_property_names,
                        foreign_class => $parent->class_name,
                        foreign_property_names => \@parent_id_property_names,
                        object_num => $object_num,
                    };
                    @last_id_property_names = @parent_id_property_names;
                    $last_class_name = $foreign_class_name;
                }
                next;
            }
            
        } # next join

        unless ($delegated_property->via) {
            next;
        }

        my $final_accessor_property_meta = $last_class_object_excluding_inherited_joins->get_property_meta_by_name($final_accessor);
        unless ($final_accessor_property_meta) {
            die "Failed to find property $final_accessor for class " . $last_class_object_excluding_inherited_joins->class_name . "!";
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

        my $operator       = $rule_template->operator_for_property_name($property_name);
        my $value_position = $rule_template->value_position_for_property_name($property_name);                
        
        unless ($alias_for_property_value) {
            die "No alias found for $property_name?!";
        }

        push @sql_filters, 
            $alias_for_property_value => { 
                $sql_lvalue => { operator => $operator, value_position => $value_position } 
            };
    } # next delegated property
    
    # Build the SELECT clause explicitly.
    $select_clause = '';
    for my $class_property (@all_table_properties) {
        my ($sql_class,$sql_property,$sql_table_name) = @$class_property;
        $sql_table_name ||= $sql_class->table_name;
        $select_clause .= ($class_property == $all_table_properties[0] ? "" : ", ");
       
        # FIXME - maybe a better way would be for these sql-calculated properties, the column_name()
        # or maybe some other related property name) is actually calculated, so this logic
        # gets encapsulated in there?
        if (my $sql_function = $sql_property->calculate_sql) {
            my @calculate_from = ref($sql_property->calculate_from) eq 'ARRAY' ? @{$sql_property->calculate_from} : ( $sql_property->calculate_from );
            foreach my $sql_column_name ( @calculate_from ) {
                $sql_function =~ s/($sql_column_name)/$sql_table_name\.$1/g;
            }
            $select_clause .= $sql_function;
        } else {
            $select_clause .= $sql_table_name . "." . $sql_property->column_name;
        }
    }
   
    # Oracle places hints in a comment in the select 
    $select_hint = $class_meta->query_hint;

    #print Data::Dumper::Dumper(\@sql_joins, \@sql_filters);

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
    
    #$DB::single = 1;    
    my $per_object_in_resultset_loading_detail = $self->_generate_loading_templates_arrayref(\@all_table_properties);
    #print Data::Dumper::Dumper($per_object_in_resultset_loading_detail);

    my $parent_template_data = $self->SUPER::_generate_template_data_for_loading($rule_template);

    my $template_data = $rule_template->{loading_data_cache} = {
        %$parent_template_data,

        # custom for RDBMS
        select_clause                               => $select_clause,
        select_hint                                 => $select_hint,
        from_clause                                 => $from_clause,        
        connect_by_clause                           => $connect_by_clause,
        order_by_clause                             => $order_by_clause,        
        filter_specs                                => \@filter_specs,
        sql_params                                  => \@sql_params,
        
        # override defaults in the regular datasource $parent_template_data
        needs_further_boolexpr_evaluation_after_loading => $needs_further_boolexpr_evaluation_after_loading,
        property_names_in_resultset_order           => \@property_names_in_resultset_order,
        properties_meta_in_resultset_order          => \@all_table_properties,
        loading_templates                           => $per_object_in_resultset_loading_detail,
    };

    return $template_data;
}


# We're overriding the method in UR::Object because we support 2 more
# event types: connect and query
sub validate_subscription {
    my ($self,$subscription_property) = @_;

    my $retval = $self->SUPER::validate_subscription(@_);
    return $retval if $retval;

    return 1 if ($subscription_property eq 'connect' or
                 $subscription_property eq 'query');

    return;
}


1;
