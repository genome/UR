package UR::DataSource::RDBMS;

# NOTE:: UR::DataSource::QueryPlan has conditional logic 
# for this class/subclasses currently

use strict;
use warnings;
use Scalar::Util;
use File::Basename;

require UR;
our $VERSION = "0.31"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::DataSource::RDBMS',
    is => ['UR::DataSource','UR::Singleton'],
    is_abstract => 1,
    properties => [
        server       => { is => 'String', doc => 'the "server" part of the DBI connect string' },
        login        => { is => 'String', doc => 'user name to connect as', is_optional => 1 },
        auth         => { is => 'String', doc => 'authentication for the given user', is_optional => 1 },
        owner        => { is => 'String', doc => 'Schema/owner name to connect to', is_optional => 1  },

        _all_dbh_hashref                 => { type => 'HASH',       len => undef, is_transient => 1 },
        _default_dbh                     => { type => 'DBI::db',    len => undef, is_transient => 1 },
        _last_savepoint                  => { type => 'String',     len => undef, is_transient => 1 },
    ],
    doc => 'A logical DBI-based database, independent of prod/dev/testing considerations or login details.',
);

sub database_exists {
    my $self = shift;
    warn $self->class . " failed to implement the database_exists() method.  Testing connection as a surrogate.  FIXME here!\n";
    eval {
        my $c = $self->create_dbh();
    };
    if ($@) {
        return;
    }
    return 1;
}

sub create_database {
    my $self = shift;
    die $self->class . " failed to implement the create_database() method!"
        . "  Unable to initialize a new database for this data source "
        . $self->__display_name__ . " FIXME here.\n";
}

sub _resolve_ddl_for_table {
    my ($self,$table) = @_;

    my $table_name = $table->table_name;
    my @ddl;
    if ($table->{db_committed}) {
        my @columns = $table->columns;
        for my $column (@columns) {
            next unless $column->last_object_revision eq '-';
            my $column_name = $column->column_name;
            my $ddl = "alter table $table_name add column ";

            $ddl .= "\t$column_name " . $column->data_type;
            if ($column->data_length) {
                $ddl .= '(' . $column->data_length . ')';
            }
            push(@ddl, $ddl) if $ddl;
        }
    }
    else {
        my $ddl;
        my @columns = $table->columns;
        for my $column (@columns) {
            next unless $column->last_object_revision eq '-';
            my $column_name = $column->column_name;
            $ddl = 'create table ' . $table_name . "(\n" unless defined $ddl;

            $ddl .= "\t$column_name " . $column->data_type;
            if ($column->data_length) {
                $ddl .= '(' . $column->data_length . ')';
            }

            $ddl .= ",\n" unless $column eq $columns[-1];
        }
        $ddl .= "\n)" if defined $ddl;
        push(@ddl, $ddl) if $ddl;
    }
    return @ddl;
}

sub generate_schema_for_class_meta {
    my ($self,$class_meta,$temp) = @_;

    # We now support on-the-fly database introspection
    # this gets called with the temp flag when _sync_database realizes 
    # it knows nothing about the table in question.
    
    # We basically presume the schema is the one we would have generated 
    # given the current class definitions

    # TODO: We still need to presume foreign keys are constrained.

    my $method = ($temp ? '__define__' : 'create'); 
    my @defined;    
    my $table_name = $class_meta->table_name;
    my @fks_to_generate;
    for my $p ($class_meta->parent_class_metas) {
        next if ($p->class_name eq 'UR::Object' or $p->class_name eq 'UR::Entity');
        next unless $p->class_name->isa("UR::Object");
        my @new = $self->generate_schema_for_class_meta($p,$temp);
        push @defined, @new;

        my $parent_table;
        if (($parent_table) = grep { $_->isa("UR::DataSource::RDBMS::Table") } @new) {
            my @id_by = $class_meta->id_property_names;            
            my @column_names = map { $class_meta->property($_)->column_name } @id_by;
            my $r_table_name = $parent_table->table_name;
            ##$DB::single = 1; # get pk columns
            my @r_id_by = $p->id_property_names;
            my @r_column_names = map { $class_meta->property($_)->column_name } @r_id_by;
            push @fks_to_generate, [$class_meta->class_name, $table_name, $r_table_name, \@column_names, \@r_column_names];
        }
    }

    my %properties_with_expected_columns = 
        map { $_->column_name => $_ } 
        grep { $_->column_name }
        $class_meta->direct_property_metas;    

    #my %expected_constraints =
    #    map { $_->column_name => $_ }
    #    grep { $_->class_meta eq $class_meta }
    #    map { $class_meta->property_meta_for_name($_) }
    #    map { @{ $_->id_by } }
    #    grep { $_->id_by }
    #    $class_meta->all_property_metas;
    #print Data::Dumper::Dumper(\%expected_constraints);
    
    unless ($table_name) {
        if (my @column_names = keys %properties_with_expected_columns) {
            Carp::confess "class " . $class_meta->__display_name__ . " has no table_name specified for columns @column_names!";
        }
        else {
            # no table, but no storable columns.  all ok.
            return;
        }
    }

    ## print "handling table $table_name\n";

    if ($table_name =~ /[^\w\.]/) {
        # pass back anything from parent classes, but do nothing for special "view" tables
        #$DB::single = 1;
        return @defined;   
    }
 
    my $t = '-'; 

    my $table = $self->refresh_database_metadata_for_table_name($table_name, $method);
 
    my %existing_columns;
    if ($table) {
        ## print "found table $table_name\n";
        %existing_columns = 
            map { $_->column_name => $_ } 
            grep { $_->column_name }
            $table->columns;
        push @defined, ($table,$table->columns);
    }
    else {
        ## print "adding table $table_name\n";
        my($ds_owner, $ds_table) = $self->_resolve_owner_and_table_from_table_name($table_name);
        $table = UR::DataSource::RDBMS::Table->$method(
            table_name  => $ds_table,
            data_source => $self->id,
            owner => $ds_owner,
            remarks => $class_meta->doc,
            er_type => 'entity',
            last_object_revision => $t,
            table_type => ($table_name =~ /\s/ ? 'view' : 'table'),
        );
        Carp::confess("Failed to create metadata or table $table_name") unless $table;
        push @defined, $table;
    }

    my ($update,$add,$extra) = _intersect_lists([keys %properties_with_expected_columns],[keys %existing_columns]);

    for my $column_name (@$extra) {
        my $column = $existing_columns{$column_name};
        $column->last_object_revision('?');
    }   
   
    for my $column_name (@$add) {
        my $property = $properties_with_expected_columns{$column_name}; 
        #print "adding column $column_name\n";
        my $column = UR::DataSource::RDBMS::TableColumn->$method(
            column_name => $column_name,
            table_name => $table->table_name,
            data_source => $table->data_source,
            namespace => $table->namespace,
            owner => $table->owner, 
            data_type => $self->object_to_db_type($property->data_type) || 'Text',
            data_length => $property->data_length,
            nullable => $property->is_optional,
            remarks => $property->doc,
            last_object_revision => $t, 
        );
        push @defined, $column;
    }

    for my $column_name (@$update) {
        my $property = $properties_with_expected_columns{$column_name}; 
        my $column = $existing_columns{$column_name};
        ##print "updating column $column_name with data from property " . $property->property_name . "\n";
        if ($column->data_type) {
            $column->data_type($self->object_to_db_type($property->data_type)) if $property->data_type;
        }
        else {
            $column->data_type($self->object_to_db_type($property->data_type) || 'Text');
        }
        $column->data_length($property->data_length);
        $column->nullable($property->is_optional);
        $column->remarks($property->doc);
    }

    for my $property ( $class_meta->direct_id_property_metas ) {

        unless (UR::DataSource::RDBMS::PkConstraintColumn->get(table_name => $table->table_name, owner => $table->owner, column_name => $property->column_name, data_source => $table->data_source)) {
            UR::DataSource::RDBMS::PkConstraintColumn->$method(
                column_name => $property->column_name,
                data_source => $table->data_source,
                owner       => $table->owner,
                rank        => $property->is_id,
                table_name  => $table->table_name );
        }
    }

    for my $property ($class_meta->properties) {
        my $id_by = $property->id_by;
        next unless $id_by;
        my $r_class_name = $property->data_type;
        my $r_class_meta = $r_class_name->__meta__;
        my $r_table_name = $r_class_meta->table_name;
        next unless $r_table_name;
        my @column_names = map { $class_meta->property($_)->column_name } @$id_by;
        my @r_column_names = map { $r_class_meta->property($_)->column_name } @{ $r_class_meta->id_property_names };

        push @fks_to_generate, [$property->id, $table_name, $r_table_name, \@column_names, \@r_column_names ];
    }

    for my $fk_to_generate (@fks_to_generate) {
        my ($fk_id, $table_name, $r_table_name, $column_names, $r_column_names) = @$fk_to_generate;
        my($ds_owner, $ds_table) = $self->_resolve_owner_and_table_from_table_name($table_name);
        my($ds_r_owner, $ds_r_table) = $self->_resolve_owner_and_table_from_table_name($r_table_name);
        
        my $fk = UR::DataSource::RDBMS::FkConstraint->$method(
            fk_constraint_name => $fk_id,
            table_name      => $ds_table,
            r_table_name    => $ds_r_table,
            owner           => $ds_owner,
            r_owner         => $ds_owner,
            data_source     => $self->id,
            last_object_revision => '-',
        );
        unless ($fk) {
            die "failed to generate an implied foreign key constraint for $table_name => $r_table_name!"
                . UR::DataSource::RDBMS::FkConstraint->error_message;
        }
        push @defined, $fk;

        for (my $n = 0; $n < @$column_names; $n++) {
            my $column_name = $column_names->[$n];
            my $r_column_name = $r_column_names->[$n];
            my %fkcol_params = ( fk_constraint_name => $fk_id,
                                 table_name      => $ds_table,
                                 column_name     => $column_name,
                                 r_table_name    => $ds_r_table,
                                 r_column_name   => $r_column_name,
                                 owner           => $ds_owner,
                                 data_source     => $self->id,
                               );

            my $fkcol = UR::DataSource::RDBMS::FkConstraintColumn->get(%fkcol_params);
            unless ($fkcol) {
                $fkcol = UR::DataSource::RDBMS::FkConstraintColumn->$method(%fkcol_params);
            }
            unless ($fkcol) {
                die "failed to generate an implied foreign key constraint for $table_name => $r_table_name!"
                    . UR::DataSource::RDBMS::FkConstraint->error_message;
            }
            push @defined, $fkcol;
        }
    }
    
    # handle missing meta datasource on the fly...
    if (@defined) {
        my $ns = $class_meta->namespace;
        my $exists = UR::Object::Type->get($ns . "::DataSource::Meta");
        unless ($exists) {
            UR::DataSource::Meta->generate_for_namespace($ns);
        }
    }

    unless ($temp) {
        my @ddl = $self->_resolve_ddl_for_table($table);
        $t = $UR::Context::current->now;
        if (@ddl) {
            my $dbh = $table->data_source->get_default_handle;
            for my $ddl (@ddl) {
                $dbh->do($ddl) or Carp::confess("Failed to modify the database schema!: $ddl\n" . $dbh->errstr);
                for my $o ($table, $table->columns) {
                    $o->last_object_revision($t);
                }
            }
        }
    }

    return @defined;
}

# why isn't something like this in List::Util?
sub _intersect_lists {
    my ($m,$n) = @_;
    my %shared;
    my %monly;
    my %nonly;
    @monly{@$m} = @$m;
    for my $v (@$n) {
        if ($monly{$v}) {
            $shared{$v} = delete $monly{$v};
        }    
        else{
            $nonly{$v} = $v;
        }
    }
    return (
        [ values %shared ],
        [ values %monly ],
        [ values %nonly ],
    );
}

# override in architecture-oriented subclasses
sub object_to_db_type {
    my ($self, $object_type) = @_;
    my $db_type = $object_type;
    # ...
    return $db_type;
}

# override in architecture-oriented subclasses
sub db_to_object_type {
    my ($self, $db_type) = @_;
    my $object_type = $db_type;
    # ...
    return $object_type;
}


# FIXME - shouldn't this be a property of the class instead of a method?
sub does_support_joins { 1 } 

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
        ##$DB::single = 1;
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

sub get_default_handle {    
    my $self = shift->_singleton_object;    
    my $dbh = $self->_default_dbh;
    unless ($dbh && $dbh->{Active}) {
        $dbh = $self->create_dbh();
        $self->_default_dbh($dbh);
    }    
    return $dbh;
}

*get_default_dbh = \&get_default_handle;
*has_default_dbh = \&has_default_handle;
*disconnect_default_dbh = \&disconnect_default_handle;

sub has_default_handle {
    my $self = shift->_singleton_object;
    return 1 if $self->_default_dbh;
    return;
}

sub disconnect_default_handle {
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
            Carp::confess("Failed to initialize new database connection!\n"
                . $self->error_message . "\n");
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

    $self->__signal_change__("connect");
    
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
    my $self = shift;

    #my $class = shift->_singleton_class_name;
    #return UR::DataSource::RDBMS::Table->get(data_source_id => $class);
    my $ds_id;
    if (ref $self) {
        if ($self->can('id')) {
            $ds_id = $self->id;
        } else {
            $ds_id = ref $self;
        }
    } else {
        $ds_id = $self;
    }
    return UR::DataSource::RDBMS::Table->get(data_source => $ds_id);
}

sub get_nullable_foreign_key_columns_for_table {
    my $self = shift;
    my $table = shift;

    my @nullable_fk_columns;

    my @fk = $table->fk_constraints;
    for my $fk (@fk){
        my @fk_columns = UR::DataSource::RDBMS::FkConstraintColumn->get(
                             fk_constraint_name => $fk->fk_constraint_name,
                             owner => $table->owner,
                             data_source => $self->id);
        for my $fk_col (@fk_columns){
            my $column_obj = UR::DataSource::RDBMS::TableColumn->get(data_source => $self->id,
                                 table_name => $fk_col->table_name,
                                 owner => $fk_col->owner,
                                 column_name=> $fk_col->column_name);
            unless ($column_obj) {
                Carp::croak("Can't find TableColumn metadata object for table name ".$fk_col->table_name." column ".$fk_col->column_name." while processing foreign key constraint named ".$fk->fk_constraint_name);
            }
            if ($column_obj->nullable and $column_obj->nullable ne 'N'){
                my $col = $column_obj->column_name;
                push @nullable_fk_columns, $col;
            }
        }
    }
    return @nullable_fk_columns;
}

sub get_non_primary_key_nullable_foreign_key_columns_for_table {
    my $self = shift;
    my $table = shift;

    my @nullable_fk_columns = $self->get_nullable_foreign_key_columns_for_table($table);
    my %pk_columns = map { $_->column_name => 1} $table->primary_key_constraint_columns;
    my @non_pk_nullable_fk_columns;
    for my $fk_column (@nullable_fk_columns){
        push @non_pk_nullable_fk_columns, $fk_column unless grep { $fk_column eq $_} keys %pk_columns;
    }
    return @non_pk_nullable_fk_columns;
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
    $vocabulary = 'UR::Vocabulary' unless eval { $vocabulary->__meta__ };
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

    if (substr($class_name, -6) eq '::Type') {
        # Don't overwrite class metadata objects for a table called 'type'
        $class_name .= 'Table';
        $self->warning_message("Class for table $table_name will be $class_name");
    }

    return $class_name;
}

sub resolve_type_name_for_table_name {
    my $self = shift->_singleton_class_name;
    my $table_name = shift;

    my $namespace = $self->get_namespace;
    my $vocabulary = $namespace->get_vocabulary;
    $vocabulary = 'UR::Vocabulary' unless eval { $vocabulary->__meta__ };

    my $vocab_obj = eval { $vocabulary->__meta__ };
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

sub refresh_database_metadata_for_table_name {
    my ($self,$db_table_name, $creation_method) = @_;

    $creation_method ||= 'create';

    my $data_source = $self;

    my $ur_table_name = $db_table_name;
    my @column_objects;
    my @all_constraints;

    # this must be on or before the actual data dictionary queries
    my $revision_time = $UR::Context::current->now();

    # We'll count a table object as changed even if any of the columns,
    # FKs, etc # were changed
    my $data_was_changed_for_this_table = 0;

    # The class definition can specify a table name as <schema>.<table_name> to override the
    # data source's default schema/owner.
    my $ds_owner;
    ($ds_owner,$db_table_name) = $self->_resolve_owner_and_table_from_table_name($db_table_name);
    my $ur_owner;
    ($ur_owner, $ur_table_name) = $self->_resolve_owner_and_table_from_table_name($ur_table_name);
    #my $dd_table_name = $table_name;
    #if ($table_name =~ m/(\w+)\.(\w+)/) {
    #    $ds_owner = $1;
    #    $dd_table_name = $2;
    #}

    # TABLE
    my $table_sth = $data_source->get_table_details_from_data_dictionary('%', $ds_owner, $db_table_name, "TABLE,VIEW");
    my $table_data = $table_sth->fetchrow_hashref();
    unless ($table_data && %$table_data) {
        #$self->error_message("No data for table $table_name in data source $data_source.");
        return;
    }

    my $data_source_id = $data_source->id;
    my $table_object = UR::DataSource::RDBMS::Table->get(data_source => $data_source_id,
                                                         owner       => $ur_owner,
                                                         table_name  => $ur_table_name);
    if ($table_object) {
        # Already exists, update the existing entry
        # Instead of deleting and recreating the table object (the old way),
        # modify its attributes in-place.  The name can't change but all the other
        # stuff might.
        $table_object->table_type($table_data->{TABLE_TYPE});
        $table_object->owner($table_data->{TABLE_SCHEM});
        $table_object->data_source($data_source->class);
        $table_object->remarks($table_data->{REMARKS});
        $table_object->last_object_revision($revision_time) if ($table_object->__changes__());

    } else {
        # Create a brand new one from scratch

        $table_object = UR::DataSource::RDBMS::Table->$creation_method(
            table_name => $ur_table_name,
            table_type => $table_data->{TABLE_TYPE},
            owner => $table_data->{TABLE_SCHEM},
            data_source => $data_source_id,
            remarks => $table_data->{REMARKS},
            last_object_revision => $revision_time,
        );
        unless ($table_object) {
            Carp::confess("Failed to $creation_method table object for $db_table_name");
        }
    }


    # COLUMNS
    # mysql databases seem to require you to actually put in the database name in the first arg
    my $db_name = ($data_source->can('db_name')) ? $data_source->db_name : '%';
    my $column_sth = $data_source->get_column_details_from_data_dictionary($db_name, $ds_owner, $db_table_name, '%');
    unless ($column_sth) {
        $self->error_message("Error getting column data for table $db_table_name in data source $data_source.");
        return;
    }
    my $all_column_data = $column_sth->fetchall_arrayref({});
    unless (@$all_column_data) {
        $self->error_message("No column data for table $db_table_name in data source $data_source_id");
        return;
    }

    my %columns_to_delete = map {$_->column_name, $_}
                                UR::DataSource::RDBMS::TableColumn->get(
                                    table_name  => $ur_table_name,
                                    owner       => $ur_owner,
                                    data_source => $data_source_id);


    for my $column_data (@$all_column_data) {

        #my $id = $table_name . '.' . $column_data->{COLUMN_NAME}
        $column_data->{'COLUMN_NAME'} =~ s/"|'//g;  # Postgres puts quotes around things that look like keywords

        delete $columns_to_delete{$column_data->{'COLUMN_NAME'}};

        my $column_obj = UR::DataSource::RDBMS::TableColumn->get(table_name  => $ur_table_name,
                                                                 owner       => $ur_owner,
                                                                 data_source => $data_source_id,
                                                                 column_name => $column_data->{'COLUMN_NAME'});
        if ($column_obj) {
            # Already exists, change the attributes
            $column_obj->owner($table_object->{owner});
            $column_obj->data_source($table_object->{data_source});
            $column_obj->data_type($column_data->{TYPE_NAME});
            $column_obj->nullable(substr($column_data->{IS_NULLABLE}, 0, 1));
            $column_obj->data_length($column_data->{COLUMN_SIZE});
            $column_obj->remarks($column_data->{REMARKS});
            if ($column_obj->__changes__()) {
                $column_obj->last_object_revision($revision_time);
                $data_was_changed_for_this_table = 1;
            }

        } else {
            # It's new, create it from scratch

            $column_obj = UR::DataSource::RDBMS::TableColumn->$creation_method(
                column_name => $column_data->{COLUMN_NAME},
                table_name  => $ur_table_name,
                owner       => $table_object->{owner},
                data_source => $table_object->{data_source},

                data_type   => $column_data->{TYPE_NAME},
                nullable    => substr($column_data->{IS_NULLABLE}, 0, 1),
                data_length => $column_data->{COLUMN_SIZE},
                remarks     => $column_data->{REMARKS},
                last_object_revision => $revision_time,
            );

            $data_was_changed_for_this_table = 1;
        }

        unless ($column_obj) {
            Carp::confess("Failed to create a column ".$column_data->{'COLUMN_NAME'}." for table $db_table_name");
        }

        push @column_objects, $column_obj;
    }

    for my $to_delete (values %columns_to_delete) {
        #$self->status_message("Detected column " . $to_delete->column_name . " has gone away.");
        $to_delete->delete;
        $data_was_changed_for_this_table = 1;
    }


    my $bitmap_data = $data_source->get_bitmap_index_details_from_data_dictionary($db_table_name);
    for my $index (@$bitmap_data) {
        #push @{ $embed{bitmap_index_names}{$table_object} }, $index->{'index_name'};

        my($ds_owner, $ds_table) = $self->_resolve_owner_and_table_from_table_name($index->{'table_name'});
        my $column_object = UR::DataSource::RDBMS::TableColumn->is_loaded(
            table_name  => $ds_table,
            owner       => $ds_owner,
            data_source => $data_source_id,
            column_name => $index->{'column_name'},
        );
    }


    # Make a note of what FKs exist in the Meta DB involving this table
    my @fks_in_meta_db = UR::DataSource::RDBMS::FkConstraint->get(data_source => $data_source_id,
                                                                  owner       => $ur_owner,
                                                                  table_name  => $ur_table_name);
    push @fks_in_meta_db, UR::DataSource::RDBMS::FkConstraint->get(data_source  => $data_source_id,
                                                                   r_owner      => $ur_owner,
                                                                   r_table_name => $ur_table_name);
    my %fks_in_meta_db_by_fingerprint;
    foreach my $fk ( @fks_in_meta_db ) {
        my $fingerprint = $self->_make_foreign_key_fingerprint($fk);
        $fks_in_meta_db_by_fingerprint{$fingerprint} = $fk;
    }

    # constraints on this table against columns in other tables


    #my $db_owner = $data_source->owner;
    my $fk_sth = $data_source->get_foreign_key_details_from_data_dictionary('', $ds_owner, $db_table_name, '', '', '');

    my %fk;     # hold the fk constraints that this invocation of foreign_key_info created

    my @constraints;
    my %fks_in_real_db;
    if ($fk_sth) {
        while (my $data = $fk_sth->fetchrow_hashref()) {

            foreach ( qw( FK_NAME FK_TABLE_NAME FKTABLE_NAME UK_TABLE_NAME PKTABLE_NAME FK_COLUMN_NAME FKCOLUMN_NAME UK_COLUMN_NAME PKCOLUMN_NAME ) ) {
                next unless defined($data->{$_});
                # Postgres puts quotes around things that look like keywords
                $data->{$_} =~ s/"|'//g;
            }

            my $constraint_name = $data->{'FK_NAME'};
            my $fk_table_name = $data->{'FK_TABLE_NAME'}
                                || $data->{'FKTABLE_NAME'};
            my $r_table_name = $data->{'UK_TABLE_NAME'}
                               || $data->{'PKTABLE_NAME'};
            my $fk_column_name = $data->{'FK_COLUMN_NAME'}
                                 || $data->{'FKCOLUMN_NAME'};
            my $r_column_name = $data->{'UK_COLUMN_NAME'}
                                || $data->{'PKCOLUMN_NAME'};

            # MySQL returns primary key info with foreign_key_info()!?
            # They show up here with no $r_table_name or $r_column_name
            next unless ($r_table_name and $r_column_name);

            my $fk = UR::DataSource::RDBMS::FkConstraint->get(fk_constraint_name => $constraint_name,
                                                              table_name         => $fk_table_name,
                                                              owner              => $table_object->{owner},
                                                              data_source        => $data_source_id,
                                                              r_table_name       => $r_table_name
                                                          );

            unless ($fk) {
                $fk = UR::DataSource::RDBMS::FkConstraint->$creation_method(
                    fk_constraint_name => $constraint_name,
                    table_name      => $fk_table_name,
                    r_table_name    => $r_table_name,
                    owner           => $table_object->{owner},
                    r_owner         => $table_object->{owner},
                    data_source     => $table_object->{data_source},
                    last_object_revision => $revision_time,
                );

                $fk{$fk->id} = $fk;
                $data_was_changed_for_this_table = 1;
            }

            if ($fk{$fk->id}) {
                my %fkcol_params = ( fk_constraint_name => $constraint_name,
                                     table_name      => $fk_table_name,
                                     column_name     => $fk_column_name,
                                     r_table_name    => $r_table_name,
                                     r_column_name   => $r_column_name,
                                     owner           => $table_object->{owner},
                                     data_source     => $table_object->{data_source},
                                   );
                my $fkcol = UR::DataSource::RDBMS::FkConstraintColumn->get(%fkcol_params);
                unless ($fkcol) {
                    $fkcol = UR::DataSource::RDBMS::FkConstraintColumn->$creation_method(%fkcol_params);
                }
            }

            my $fingerprint = $self->_make_foreign_key_fingerprint($fk);
            $fks_in_real_db{$fingerprint} = $fk;

            push @constraints, $fk;
        }
    }

    # get foreign_key_info the other way
    # constraints on other tables against columns in this table

    my $fk_reverse_sth = $data_source->get_foreign_key_details_from_data_dictionary('', '', '', '', $ds_owner, $db_table_name);

    %fk = ();   # resetting this prevents data_source referencing
    # tables from fouling up their fk objects


    if ($fk_reverse_sth) {
        while (my $data = $fk_reverse_sth->fetchrow_hashref()) {

            foreach ( qw( FK_NAME FK_TABLE_NAME FKTABLE_NAME UK_TABLE_NAME PKTABLE_NAME FK_COLUMN_NAME FKCOLUMN_NAME UK_COLUMN_NAME PKCOLUMN_NAME PKTABLE_SCHEM FKTABLE_SCHEM UK_TABLE_SCHEM FK_TABLE_SCHEM) ) {
                next unless defined($data->{$_});
                # Postgres puts quotes around things that look like keywords
                $data->{$_} =~ s/"|'//g;
            }

            my $constraint_name = $data->{'FK_NAME'};
            my $fk_table_name = $data->{'FK_TABLE_NAME'}
                                || $data->{'FKTABLE_NAME'};
            my $r_table_name = $data->{'UK_TABLE_NAME'}
                               || $data->{'PKTABLE_NAME'};
            my $fk_column_name = $data->{'FK_COLUMN_NAME'}
                                 || $data->{'FKCOLUMN_NAME'};
            my $r_column_name = $data->{'UK_COLUMN_NAME'}
                                || $data->{'PKCOLUMN_NAME'};
            my $owner         = $data->{'FK_TABLE_SCHEM'}
                                || $data->{'FKTABLE_SCHEM'}
                                || $table_object->owner;
            my $r_owner       = $data->{'UK_TABLE_SCHEM'}
                                || $data->{'PKTABLE_SCHEM'}
                                || $table_object->owner;

            # MySQL returns primary key info with foreign_key_info()?!
            # They show up here with no $r_table_name or $r_column_name
            next unless ($r_table_name and $r_column_name);

            my $fk = UR::DataSource::RDBMS::FkConstraint->get(fk_constraint_name => $constraint_name,
                                                              table_name         => $fk_table_name,
                                                              owner              => $owner,
                                                              r_table_name       => $r_table_name,
                                                              r_owner            => $r_owner,
                                                              data_source        => $table_object->{'data_source'},
                                                          );
            unless ($fk) {
                $fk = UR::DataSource::RDBMS::FkConstraint->$creation_method(
                    fk_constraint_name => $constraint_name,
                    table_name      => $fk_table_name,
                    r_table_name    => $r_table_name,
                    owner           => $owner,
                    r_owner         => $r_owner,
                    data_source     => $table_object->{data_source},
                    last_object_revision => $revision_time,
                );
                unless ($fk) {
                    ##$DB::single = 1;
                    1;
                }
                $fk{$fk->fk_constraint_name} = $fk;
                $data_was_changed_for_this_table = 1;
            }

            if ($fk{$fk->fk_constraint_name}) {
                my %fkcol_params = ( fk_constraint_name => $constraint_name,
                                     table_name      => $fk_table_name,
                                     column_name     => $fk_column_name,
                                     r_table_name    => $r_table_name,
                                     r_column_name   => $r_column_name,
                                     owner           => $owner,
                                     data_source     => $table_object->{data_source},
                                 );
                unless ( UR::DataSource::RDBMS::FkConstraintColumn->get(%fkcol_params) ) {
                    UR::DataSource::RDBMS::FkConstraintColumn->$creation_method(%fkcol_params);
                }
            }


            my $fingerprint = $self->_make_foreign_key_fingerprint($fk);
            $fks_in_real_db{$fingerprint} = $fk;

            push @constraints, $fk;
        }
    }

    # Find FKs still in the Meta db that don't exist in the real database anymore
    foreach my $fingerprint ( keys %fks_in_meta_db_by_fingerprint ) {
        unless ($fks_in_real_db{$fingerprint}) {
            my $fk = $fks_in_meta_db_by_fingerprint{$fingerprint};
            my @fk_cols = $fk->get_related_column_objects();
            $_->delete foreach @fk_cols;
            $fk->delete;
        }
    }

    # get primary_key_info

    my $pk_sth = $data_source->get_primary_key_details_from_data_dictionary(undef, $ds_owner, $db_table_name);

    if ($pk_sth) {
        my @new_pk;
        while (my $data = $pk_sth->fetchrow_hashref()) {
            $data->{'COLUMN_NAME'} =~ s/"|'//g;  # Postgres puts quotes around things that look like keywords
            my $pk = UR::DataSource::RDBMS::PkConstraintColumn->get(
                table_name  => $ur_table_name,
                owner       => $ur_owner,
                data_source => $data_source_id,
                column_name => $data->{'COLUMN_NAME'},
            );
            if ($pk) {
                # Since the rank/order is pretty much all that might change, we
                # just delete and re-create these.
                # It's a no-op at save time if there are no changes.
                $pk->delete;
            }

            push @new_pk, [
                            table_name => $ur_table_name,
                            data_source => $data_source_id,
                            owner => $ds_owner,
                            column_name => $data->{'COLUMN_NAME'},
                            rank => $data->{'KEY_SEQ'} || $data->{'ORDINAL_POSITION'},
                        ];
            #        $table_object->{primary_key_constraint_name} = $data->{PK_NAME};
            #        $embed{primary_key_constraint_column_names} ||= {};
            #        $embed{primary_key_constraint_column_names}{$table_object} ||= [];
            #        push @{ $embed{primary_key_constraint_column_names}{$table_object} }, $data->{COLUMN_NAME};
        }

        for my $data (@new_pk) {
            my $pk = UR::DataSource::RDBMS::PkConstraintColumn->$creation_method(@$data);
            unless ($pk) {
                $self->error_message("Failed to create primary key @$data");
                return;
            }
        }			
    }

    ## Get the unique constraints
    ## Unfortunately, there appears to be no DBI catalog
    ## method which will find these.  So we have to use
    ## some custom SQL
    #
    # The SQL that used to live here was moved to the UR::DataSource::Oracle
    # and each other DataSource class needs its own implementation

    # The above was moved into each data source's class
    if (my $uc = $data_source->get_unique_index_details_from_data_dictionary($db_table_name)) {
        my %uc = %$uc;   # make a copy we can manipulate in case $uc is shared or read-only

        # check for redundant unique constraints
        # there may be both an index and a constraint

        for my $uc_name_1 ( keys %uc ) {

            my $uc_columns_1 = $uc{$uc_name_1}
                or next;
            my $uc_columns_1_serial = join ',', sort @$uc_columns_1;

            for my $uc_name_2 ( keys %uc ) {
                next if ( $uc_name_2 eq $uc_name_1 );
                my $uc_columns_2 = $uc{$uc_name_2}
                    or next;
                my $uc_columns_2_serial = join ',', sort @$uc_columns_2;

                if ( $uc_columns_2_serial eq $uc_columns_1_serial ) {
                    delete $uc{$uc_name_1};
                }
            }
        }

        # compare primary key constraints to unique constraints
        my $pk_columns_serial =
            join(',',
                sort map { $_->column_name }
                    UR::DataSource::RDBMS::PkConstraintColumn->get(
                        data_source => $data_source_id,
                        table_name => $ur_table_name,
                        owner => $ds_owner,
                    )
                );
        for my $uc_name ( keys %uc ) {

            # see if primary key constraint has the same name as
            # any unique constraints
            # FIXME - disabling this for now, the Meta DB dosen't track PK constraint names
            # Isn't it just as goot to check the involved columns?
            #if ( $table_object->primary_key_constraint_name eq $uc_name ) {
            #    delete $uc{$uc_name};
            #    next;
            #}

            # see if any unique constraints cover the exact same column(s) as
            # the primary key column(s)
            my $uc_columns_serial = join ',', sort @{ $uc{$uc_name} };

            if ( $pk_columns_serial eq $uc_columns_serial ) {
                delete $uc{$uc_name};
            }
        }

        # Create new UniqueConstraintColumn objects for the columns that don't exist, and delete the
        # objects if they don't apply anymore
        foreach my $uc_name ( keys %uc ) {
            my %constraint_objs =
                map { $_->column_name => $_ }
                UR::DataSource::RDBMS::UniqueConstraintColumn->get(
                    data_source => $data_source_id,
                    table_name => $ur_table_name,
                    owner => $ds_owner || '',
                    constraint_name => $uc_name,
                );

            foreach my $col_name ( @{$uc{$uc_name}} ) {
                if ($constraint_objs{$col_name} ) {
                    delete $constraint_objs{$col_name};
                } else {
                    my $uc = UR::DataSource::RDBMS::UniqueConstraintColumn->$creation_method(
                        data_source => $data_source_id,
                        table_name => $ur_table_name,
                        owner => $ds_owner,
                        constraint_name => $uc_name,
                        column_name => $col_name,
                    );
                    1;
                }
            } 
            foreach my $obj ( values %constraint_objs ) {
                $obj->delete();
            }
        }
    }

    $table_object->last_object_revision($revision_time) if ($data_was_changed_for_this_table);

    # Now that all columns know their foreign key constraints,
    # have the column objects resolve the various names
    # associated with the column.

    #for my $col (@column_objects) { $col->resolve_names }

    # Determine the ER type.
    # We have 'validation item', 'entity', and 'bridge'

    my $column_count = scalar($table_object->column_names) || 0;
    my $pk_column_count = scalar($table_object->primary_key_constraint_column_names) || 0;
    my $constraint_count = scalar($table_object->fk_constraint_names) || 0;

    if ($column_count == 1 and $pk_column_count == 1) {
        $table_object->er_type('validation item');
    }
    else {
        if ($constraint_count == $column_count) {
            $table_object->er_type('bridge');
        }
        else {
            $table_object->er_type('entity');
        }
    }

    return $table_object;
}

sub _make_foreign_key_fingerprint {
    my($self,$fk) = @_;

    my @fk_cols = sort {$a->column_name cmp $b->column_name} $fk->get_related_column_objects();
    my $fingerprint =
        join(':',
            $fk->table_name,
            $fk->r_table_name,
            map { $_->column_name, $_->r_column_name } @fk_cols
        );
    return $fingerprint;
}


sub _resolve_owner_and_table_from_table_name {
    my($self, $table_name) = @_;

    if ($table_name =~ m/(\w+)\.(\w+)/) {
        return($1,$2);
    } 
    else {
        return($self->owner, $table_name);
    }
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
# the other data_dictionary methods.  These two return hashrefs of massaged
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

    my $class_meta = UR::Object::Type->get(class_name => $class_name);
    my $sequence = $class_meta->id_generator;

    # FIXME Child classes really should use the same sequence generator as its parent
    # if it doesn't specify its own.
    # It'll be hard to distinguish the case of a class meta not explicitly mentioning its
    # sequence name, but there's a sequence generator in the schema for it (the current
    # mechanism), and when we should defer to the parent's sequence...
    unless ($sequence) {
        # This class directly doesn't have a sequence specified.  Search through the inheritance
        my $table_name;
        for my $parent_class_name ($class_name, $class_name->inheritance) {
            # print "checking $parent_class_name (for $class_name)\n";
            my $parent_class = UR::Object::Type->get(class_name => $parent_class_name);
            # print "object $parent_class\n";
            next unless $parent_class;
            #$sequence = $class_meta->id_generator;
            #last if $sequence;
            if ($table_name = $parent_class->table_name) {
                # print "found table $table_name\n";
                last;
            }
        }

        unless ($table_name) {
            Carp::croak("Could not determine a table name for class $class_name");
        }

        my($ds_owner, $ds_table) = $self->_resolve_owner_and_table_from_table_name($table_name);
        my $table_meta = UR::DataSource::RDBMS::Table->get(
                             table_name => $ds_table,
                             owner => $ds_owner,
                             data_source => $self->id);

        my @primary_keys;
        if ($table_meta) {
            @primary_keys = $table_meta->primary_key_constraint_column_names;
            $sequence = $self->_get_sequence_name_for_table_and_column($table_name, $primary_keys[0]);
        } else {
            # No metaDB info... try and make a guess based on the class' ID properties
            for my $meta ($class_meta, $class_meta->ancestry_class_metas) {
                @primary_keys = grep { $_ }  # Only interested in the properties with columns defined
                                map { $_->column_name }
                                $meta->direct_id_property_metas;
                if (@primary_keys > 1) {
                    Carp::croak("Tables with multiple primary keys (i.e. " .
                        $table_name  . ": " .
                        join(',',@primary_keys) .
                        ") cannot have a surrogate key created from a sequence.");
                } 
                elsif (@primary_keys == 1) {
                    $sequence = $self->_get_sequence_name_for_table_and_column($table_name, $primary_keys[0]);
                    last if $sequence;
                }
            }
        }

        if (@primary_keys == 0) {
            Carp::croak("No primary keys found for table " . $table_name . "\n");
        }
        if (!$sequence) {
            Carp::croak("No identity generator found for table " . $table_name . "\n");
        }
    }

    my $new_id = $self->_get_next_value_from_sequence($sequence);
    return $new_id;
}

sub _get_sequence_name_for_table_and_column {
    my($self,$table_name,$column_name) = @_;

    # The default is to take the column name (should be a primary key from a table) and
    # change the _ID at the end of the column name with _SEQ
    # if column_name is all uppercase, make the sequence name end in upper case _SEQ
    my $replacement = $column_name eq uc($column_name) ? '_SEQ' : '_seq';
    $column_name =~ s/_ID/$replacement/i;
    return $column_name;
}

sub create_iterator_closure_for_rule {
    my ($self, $rule) = @_; 

    my ($rule_template, @values) = $rule->template_and_values();    
    my $query_plan = $self->_resolve_query_plan($rule_template); 

    #
    # the template has general class data
    #

    my $class_name                                  = $query_plan->{class_name};
    my $class = $class_name;    

    my @lob_column_names                            = @{ $query_plan->{lob_column_names} };
    my @lob_column_positions                        = @{ $query_plan->{lob_column_positions} };    
    my $query_config                                = $query_plan->{query_config}; 

    my $post_process_results_callback               = $query_plan->{post_process_results_callback};

    #
    # the template has explicit template data
    #

    my $select_clause                               = $query_plan->{select_clause};
    my $select_hint                                 = $query_plan->{select_hint};
    my $from_clause                                 = $query_plan->{from_clause};
    my $where_clause                                = $query_plan->{where_clause};
    my $connect_by_clause                           = $query_plan->{connect_by_clause};
    my $group_by_clause                             = $query_plan->{group_by_clause};
    my $order_by_columns                            = $query_plan->{order_by_columns} || [];

    my $sql_params                                  = $query_plan->{sql_params};
    my $filter_specs                                = $query_plan->{filter_specs};

    my @property_names_in_resultset_order           = @{ $query_plan->{property_names_in_resultset_order} };

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
    my $order_by_clause;
    if (@$order_by_columns) {
        $order_by_clause = 'order by ' . join(', ',@$order_by_columns);
    }

    my $sql = "\nselect ";
    if ($select_hint) {
        $sql .= $select_hint . " ";
    }
    $sql .= $select_clause;
    $sql .= "\nfrom $from_clause";
    $sql .= "\n$where_clause" if defined($where_clause) and length($where_clause);
    $sql .= "\n$connect_by_clause" if $connect_by_clause;
    $sql .= "\n$group_by_clause" if $group_by_clause;
    $sql .= "\n$order_by_clause" if $order_by_clause;

    my $dbh = $self->get_default_dbh;    
    my $sth = $dbh->prepare($sql,$query_config);
    unless ($sth) {
        $class->error_message("Failed to prepare SQL $sql\n" . $dbh->errstr . "\n");
        Carp::confess($class->error_message);
    }
    unless ($sth->execute(@all_sql_params)) {
        $class->error_message("Failed to execute SQL $sql\n" . $sth->errstr . "\n" . Data::Dumper::Dumper(\@all_sql_params) . "\n");
        Carp::confess($class->error_message);
    }

    die unless $sth;   # FIXME - this has no effect, right?  

    $self->__signal_change__('query',$sql);
    
    # buffers for the iterator
    my $next_db_row;
    my $pending_db_object_data;

    my $ur_test_filldb = $ENV{'UR_TEST_FILLDB'};

    my $iterator = sub {
        unless ($sth) {
            ##$DB::single = 1;
            return;
        }

        $next_db_row = $sth->fetchrow_arrayref;
        #$self->__signal_change__('fetch',$next_db_row);  # FIXME: commented out because it may make fetches too slow

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

    Sub::Name::subname('UR::DataSource::RDBMS::__datasource_iterator(closure)__', $iterator);
    return $iterator;
}

sub _sql_like_supports_escape {
    return 1;  # Most RDBMSs support an 'escape' as part of a 'like' operator, excapt mysql
}

# This allows the size of an autogenerated IN-clause to be adjusted.
# The limit for Oracle is 1000, and a bug requires that, in some cases
# we drop to 250.
my $in_clause_size_limit = 250;        

# This method is used when generating SQL for a rule template, in the joins
# and also on a per-query basis to turn specific values into a where clause
sub _extend_sql_for_column_operator_and_value {
    my ($self, $expr_sql, $op, $val, $escape) = @_;

    $op ||= '';
    if ($op eq 'in' and not ref($val) eq 'ARRAY') {
        ##$DB::single = 1;
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
    elsif ($op =~ m/^between( \[\])?/i) {
        $sql .= "$expr_sql between ? and ?";
        push @sql_params, @$val;
    }
    elsif ($op =~ /\[\]/ or $op =~ /in/i) {
        no warnings 'uninitialized';
        my $not = $op =~ m/not/i;

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
            $sql .= ' not ' if $not;
            $sql .= " in (" . join(",",map { "'$_'" } @set) . ")";
        }
        if ($has_null) {
            $sql .= "\n  or $expr_sql is ";
            $sql .= 'not' if ($not);
            $sql .= ' null';
        }
        $sql .= "\n)\n" if $wrap;
    }       
    elsif($op =~ /^(like|not like|in|not in|\<\>|\<|\>|\=|\<\=|\>\=)$/i ) {
        # SQL operator.  Use this directly.
        $sql .= "$expr_sql $op ?";
        push @sql_params, $val;        
        if($op =~ /like/i and $self->_sql_like_supports_escape) {
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
    } elsif ($op eq 'true' ) {
        $sql .= "( $expr_sql is not null and $expr_sql != 0 )";
    } elsif ($op eq 'false' ) {
        $sql .= "( $expr_sql is null or $expr_sql = 0)";

    } else {
        # Something else?
        die "Unknown operator $op!";
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

    my $class_meta = $class_name->__meta__;
    my @id_columns = map
                         { $class_meta->property_meta_for_name($_)->column_name } 
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
        my @id_vals = map { $data->{$_} } @id_columns;
        my $cid = $class_name->__meta__->resolve_composite_id_from_ordered_values(@id_vals);
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
                    my($ds_owner, $ds_table) = $self->_resolve_owner_and_table_from_table_name($table_name);
                    my $table =
                        UR::DataSource::RDBMS::Table->get(
                            table_name => $ds_table,
                            owner => $ds_owner,
                            data_source => $self->class)
                        ||
                        UR::DataSource::RDBMS::Table->get(
                            table_name => $ds_table,
                            owner => $ds_owner,
                            data_source => 'UR::DataSource::Meta');

                    my $fully_qualified_table_name = defined $ds_owner ? join('.', $ds_owner, $ds_table) : $ds_table;
                    if ($change->{type} eq 'insert')
                    {
                        push @{ $insert{$fully_qualified_table_name} }, $change;
                    }
                    elsif ($change->{type} eq 'update')
                    {
                        push @{ $update{$fully_qualified_table_name} }, $change;
                    }
                    elsif ($change->{type} eq 'delete')
                    {
                        push @{ $delete{$fully_qualified_table_name} }, $change;
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
        my($ds_owner, $ds_table) = $self->_resolve_owner_and_table_from_table_name($table_name);
        my $table_object = UR::DataSource::RDBMS::Table->get(
                               table_name => $ds_table,
                               owner => $ds_owner,
                               data_source => $self->class)
                           ||
                           UR::DataSource::RDBMS::Table->get(
                               table_name => $ds_table,
                               owner => $ds_owner,
                               data_source => 'UR::DataSource::Meta');

        unless ($table_object) {
            warn "looking up schema for RDBMS table $table_name...\n";
            $table_object = $self->refresh_database_metadata_for_table_name($table_name);
            unless ($table_object) {
                die "Failed to generate table data for $table_name!";
            }
        }

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
                        table_name  => $ds_table,
                        owner       => $ds_owner,
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

    for my $table_name_from_class (keys %all_tables) {
        my($ds_owner,$ds_table) = $self->_resolve_owner_and_table_from_table_name($table_name_from_class);
        my $table = UR::DataSource::RDBMS::Table->get(
                        table_name => $ds_table,
                        owner => $ds_owner,
                        data_source => $self->class)
                    ||
                    UR::DataSource::RDBMS::Table->get(
                        table_name => $ds_table,
                        owner => $ds_owner,
                        data_source => 'UR::DataSource::Meta');

        my @fk = $table->fk_constraints;

        my $table_name = defined $ds_owner ? join('.', $ds_owner, $ds_table) : $ds_table;
        my $matched_table_name;
        if ($insert{$table_name})
        {
            $matched_table_name = 1;
            $all_table_commands{"insert $table_name"} = 1;
        }

        if ($update{$table_name})
        {
            $matched_table_name = 1;
            $all_table_commands{"update $table_name"} = 1;
        }

        if ($delete{$table_name})
        {
            $matched_table_name = 1;
            $all_table_commands{"delete $table_name"} = 1;
        }

        unless ($matched_table_name) {
            Carp::carp("Possible metadata inconsistency: A change on table $table_name was not an insert, update or delete!");
        }

        my $tmparray;

        # handle multiple differnt ops on the same table
        if ($insert{$table_name} and $update{$table_name}) {
            # insert before update
            $tmparray = $prerequisites{"update $table_name"}{"insert $table_name"} ||= [];
            $tmparray = $dependants{"insert $table_name"}{"update $table_name"} ||= [];
        }
        if ($delete{$table_name} and $update{$table_name}) {
            # update before delete
            $tmparray = $prerequisites{"delete $table_name"}{"update $table_name"} ||= [];
            $tmparray = $dependants{"update $table_name"}{"delete $table_name"} ||= [];
        }
        if ($delete{$table_name} and $insert{$table_name} and not $update{$table_name}) {
            # delete before insert
            $tmparray = $prerequisites{"insert $table_name"}{"delete $table_name"} ||= [];
            $tmparray = $dependants{"delete $table_name"}{"insert $table_name"} ||= [];
        }
        
        # Go through the constraints.
        for my $fk (@fk)
        {
            my $r_table = $fk->r_table_name;
            my $r_owner = $fk->r_owner;

            my $r_table_name = defined $r_owner ? join('.', $r_owner, $r_table) : $r_table;

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
            #print STDERR Data::Dumper::Dumper(\%objects_by_class_name, \%prerequisites, \%dependants ) . "\n";
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
            my $is_loaded_class =
                ($dml_type eq 'delete')
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
                    ##$DB::single = 1;
                    Carp::confess("Circular foreign key!") unless $main::skip_croak;
                }
                $adding{$cmd} = 1;
                my $obj = $objs{$cmd->{id}};
                my $class_meta = $obj->class->__meta__;
                for my $rcol_set (@rcol_sets) {
                    my @ordered_values = map { $obj->$_ }
                                         map { $class_meta->property_for_column($_) }
                                         @$rcol_set;
                    my $pid = $obj->class->__meta__->resolve_composite_id_from_ordered_values(@ordered_values);
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
                @local_explicit_commands = reverse @local_explicit_commands;
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
            my $class_object = $class_name->__meta__;
            unless ($tables) {                
                my $tables;
                my @all_table_names = $class_object->all_table_names;                
                for my $table_name (@all_table_names) {                    
                    my($ds_owner, $ds_table) = $self->_resolve_owner_and_table_from_table_name($table_name);
                    my $table = UR::DataSource::RDBMS::Table->get(
                                    table_name => $ds_table,
                                    owner => $ds_owner,
                                    data_source => $self->class)
                                ||
                                UR::DataSource::RDBMS::Table->get(
                                    table_name => $ds_table,
                                    owner => $ds_owner,
                                    data_source => 'UR::DataSource::Meta');
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

            my @column_objects;
            foreach my $column_name ( @{ $cmd->{column_names} } ) {
                my $column = $column_objects_by_class_and_column_name{$class_name}->{$column_name};
                unless ($column) {
                    #print "looking at parent classes for $class_name\n";
                    FIND_IN_ANCESTRY:
                    for my $ancestor_class_name ($class_object->ancestry_class_names) {
                        $column = $column_objects_by_class_and_column_name{$ancestor_class_name}->{$column_name};
                        if ($column) {
                            $column_objects_by_class_and_column_name{$class_name}->{$column_name} = $column;
                            last FIND_IN_ANCESTRY;
                        }
                        unless ($column) {
                            Carp::croak("Failed to find column metadata for column named '$column_name' for class $class_name");
                        }
                    }
                }
                push @column_objects, $column;
            }

            # print "Column Types: @column_types\n";

            for my $n (0 .. $#column_objects) {
                if ($column_objects[$n]->data_type eq 'BLOB')
                {
                    $sth->bind_param($n+1, undef, { ora_type => 23 });
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
            my($ds_owner, $ds_table) = $self->_resolve_owner_and_table_from_table_name($table_name);
            my $table = UR::DataSource::RDBMS::Table->get(
                            table_name => $ds_table,
                            owner => $ds_owner,
                            data_source => $self->class)
                        ||
                        UR::DataSource::RDBMS::Table->get(
                            table_name => $ds_table,
                            owner => $ds_owner,
                            data_source => 'UR::DataSource::Meta');
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
                #$UR::Context::current->send_email(
                #    To => 'example@example.edu',
                #    From => UR::Context::Process->prog_name . ' <example@example.edu>',
                #    Subject => (
                #            $failed_attempts >= $max_failed_attempts
                #            ? "sync_database lock failure after $failed_attempts attempts"
                #            : "sync_database lock success after $failed_attempts attempts"
                #        )
                #        . " in " . UR::Context::Process->prog_name
                #        . " on $table_name",
                #    Message => qq/
                #        $failed_attempts attempts to lock table $table_name
                #
                #        Errors:
                #        $err
                #
                #        The complete table lock list for this sync:
                #        @tables_requiring_lock
                #    /
                #);
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
                # my $dbh = UR::Context->resolve_data_source_for_object($cmd->{class})->get_default_dbh;
                push @failures, {cmd => $cmd, error_message => $sth{$cmd->{sql}}->errstr};
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
                    $self->error_message($self->id . ": Error executing SQL:\n$error->{cmd}{sql}\n" .
                                         "PARAMS: " . join(', ',map { defined($_) ? "'$_'" : '(undef)' } @{$error->{cmd}{params}}) . "\n" .
                                         $error->{error_message} . "\n");
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
        if (!$savepoint or $savepoint eq "NONE") {
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

sub _id_values_for_primary_key {
    my ($self,$table_obj,$object_to_save) = @_;

    unless ($table_obj && $object_to_save) {
        Carp::confess("Both table and object_to_save should be passed for $self!");
    }

    my $class_obj; # = $object_to_save->__meta__;
    foreach my $possible_class_obj ($object_to_save->__meta__->all_class_metas) {
        next unless ($possible_class_obj->table_name);
        my($class_owner,$class_table) = $self->_resolve_owner_and_table_from_table_name($possible_class_obj->table_name);
        # Some data sources can (used to?) have NULL owner/schema
        $class_owner = '' unless defined($class_owner);
        my $table_obj_owner = $table_obj->owner;
        $table_obj_owner = '' unless defined ($table_obj_owner);

        if ( $class_owner eq $table_obj_owner
             and
             $class_table eq $table_obj->table_name
           ) {

            $class_obj = $possible_class_obj;
            last;
        }
    }
    unless (defined $class_obj) {
        Carp::croak("Can't find class object with table " . $table_obj->table_name . " while searching inheritance for object of class ".$self->class);
    }

    my @pk_cols = $table_obj->primary_key_constraint_column_names;
    my %pk_cols = map { $_ => 1 } @pk_cols;
    # this previously went to $object_to_save->__meta__, which is nearly the same thing but not quite
    my @values = $class_obj->resolve_ordered_values_from_composite_id($object_to_save->id);
    my @columns = $class_obj->direct_id_column_names;

    foreach my $col_in_class ( @columns ) {
        unless ($pk_cols{$col_in_class}) {
            my $table_name = $table_obj->table_name;
            my $class_name = $class_obj->class_name;
            Carp::croak("While committing, metadata for table $table_name does not match class $class_name.\n  Table primary key columns are " .
                        join(', ',@pk_cols) .
                        "\n  class ID property columns " .
                        join('', @columns));
        }
    }

    my $i=0;    
    my %column_index = map { $_ => $i++ } @columns;
    my @bad_pk_cols = grep { ! exists($column_index{$_}) } @pk_cols;
    if (@bad_pk_cols) {
        my $table_name = $table_obj->table_name;
        Carp::croak("Metadata for table $table_name is inconsistent with class ".$class_obj->class_name.".\n"
                    . "Column(s) named " . join(',',@bad_pk_cols) . " appear as primary key constraint columns, "
                    . "but do not appear as ID column names.  Check the dd_pk_constraint_columns data in the "
                    . "MetaDB and the ID properties of the class definition");
    }

    my @id_values_in_pk_order = @values[@column_index{@pk_cols}];

    return @id_values_in_pk_order;
}

sub _default_save_sql_for_object {
    my $self = shift;        
    my $object_to_save = shift;
    my %params = @_;

    my ($class,$id) = ($object_to_save->class, $object_to_save->id);

    my $class_object = $object_to_save->__meta__;

    # This object may have uncommitted changes already saved.  
    # If so, work from the last saved data.
    # Normally, we go with the last committed data.

    my $compare_version = ($object_to_save->{'db_saved_uncommitted'} ? 'db_saved_uncommitted' : 'db_committed');

    # Determine what the overall save action for the object is,
    # and get a specific change summary if we're doing an update.

    my ($action,$change_summary);
    if ($object_to_save->isa('UR::Object::Ghost'))
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
        grep { not /[^\w\.]/ } # remove any views from the list
        $class_object->all_table_names;

    @save_table_names = reverse @save_table_names unless ($object_to_save->isa('UR::Entity::Ghost'));

    my @commands;
    for my $table_name (@save_table_names)
    {
        my ($db_owner, $table_name_to_update) = $self->_resolve_owner_and_table_from_table_name($table_name);
        # Get general info on the table we're working-with.                

        my $dsn = ref($self) ? $self->id : $self;  # The data source name

        my $table = UR::DataSource::RDBMS::Table->get(
                        table_name => $table_name_to_update,
                        owner => $db_owner,
                        data_source => $dsn)
                    ||
                    UR::DataSource::RDBMS::Table->get(
                        table_name => $table_name_to_update,
                        owner => $db_owner,
                        data_source => 'UR::DataSource::Meta');
        unless ($table) {
            $self->generate_schema_for_class_meta($class_object,1);
            # try again...
            $table = UR::DataSource::RDBMS::Table->get(
                         table_name => $table_name_to_update,
                         owner => $db_owner,
                         data_source => $dsn)
                     ||
                     UR::DataSource::RDBMS::Table->get(
                         table_name => $table_name_to_update,
                         owner => $db_owner,
                         data_source => 'UR::DataSource::Meta');
            unless ($table) {
                Carp::croak("No table $table_name found for data source $dsn and owner '$db_owner'");
            }
        }        
        my @table_class_obj = grep { $_->class_name !~ /::Ghost$/ } UR::Object::Type->is_loaded(table_name => $table_name);
        my $table_class;
        my $table_class_obj;
        if (@table_class_obj == 1) {
            $table_class_obj = $table_class_obj[0]; 
            $table_class = $table_class_obj->class_name; 
        }
        else {
            Carp::croak("NO CLASS FOR $table_name: @table_class_obj!\n");
        }        


        my $data_source = $UR::Context::current->resolve_data_source_for_object($object_to_save);
        unless ($data_source) {
            Carp::croak("Couldn't resolve data source for object ".$object_to_save->__display_name__.":\n"
                        . Data::Dumper::Dumper($object_to_save));
        }

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

            #grab fk_constraints so we can undef non primary-key nullable fks before delete
            my @non_pk_nullable_fk_columns = $self->get_non_primary_key_nullable_foreign_key_columns_for_table($table);

            @values = $self->_id_values_for_primary_key($table,$object_to_save);
            my $where = $self->_matching_where_clause($table, \@values);

            if (@non_pk_nullable_fk_columns) {
                #generate an update statement to set nullable fk columns to null pre delete
                my $update_sql = "UPDATE ";
                $update_sql .= "${db_owner}." if ($db_owner);
                $update_sql .= "$table_name_to_update SET ";
                $update_sql .= join(", ", map { "$_=?"} @non_pk_nullable_fk_columns);
                $update_sql .= " WHERE $where";
                my @update_values = @values;
                for (@non_pk_nullable_fk_columns){
                    unshift @update_values, undef;
                }
                my $update_command = { type         => 'update',
                                       table_name   => $table_name,
                                       column_names => \@non_pk_nullable_fk_columns,
                                       sql          => $update_sql,
                                       params       => \@update_values,
                                       class        => $table_class,
                                       id           => $id,
                                       dbh          => $data_source->get_default_dbh
                                     };
                push @commands, $update_command;
            }


            $sql = " DELETE FROM ";
            $sql .= "${db_owner}." if ($db_owner);
            $sql .= "$table_name_to_update WHERE $where";

            push @commands, { type         => 'delete',
                              table_name   => $table_name,
                              column_names => undef,
                              sql          => $sql,
                              params       => \@values,
                              class        => $table_class,
                              id           => $id,
                              dbh          => $data_source->get_default_dbh
                           };

            #print Data::Dumper::Dumper \@commands;
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
                Carp::croak("No column in table $table_name for property $property?") unless $column_name;
                push @changed_cols, $column_name;
                push @values, $changes_for_this_table->{$property};
            }

            #$object_to_save->debug_message("Changed cols: @changed_cols", 4);

            if (@changed_cols)
            {
                my @changed_values = map { defined ($_) && $object_to_save->can($_)
                                           ? $object_to_save->$_
                                           : undef }
                                     map { $class_object->property_for_column($_) || undef }
                                     @changed_cols;

                my @id_values = $self->_id_values_for_primary_key($table,$object_to_save);

                if (scalar(@changed_cols) != scalar(@changed_values)) {
                   no warnings 'uninitialized';
                   my $mapping = join("\n", map { "  $_ => ".$class_object->property_for_column($_) } @changed_cols);
                   Carp::croak("Column count mismatch while updating table $table_name_to_update.  "
                               . "The table metadata expects to see ".scalar(@changed_cols)
                               . " columns, but ".scalar(@values)." were retrieved from the object of type "
                               . $object_to_save->class . ".\nCurrent column => property mapping:\n$mapping\n"
                               . "There is probably a mismatch between the database column metadata and the column_name "
                               . "property metadata");
                }

                my @all_values = ( @changed_values, @id_values );
                my $where = $self->_matching_where_clause($table, \@all_values);

                $sql = " UPDATE ";
                $sql .= "${db_owner}." if ($db_owner);
                $sql .= "$table_name_to_update SET " . join(",", map { "$_ = ?" } @changed_cols) . " WHERE $where";

                push @commands, { type         => 'update',
                                  table_name   => $table_name,
                                  column_names => \@changed_cols,
                                  sql          => $sql,
                                  params       => \@all_values,
                                  class        => $table_class,
                                  id           => $id,
                                  dbh          => $data_source->get_default_dbh
                                };
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
                           defined($_) && $object_to_save->can($_)
                           ? $object_to_save->$_
                           : undef
                       }
                       map { $class_object->property_for_column($_) || undef }
                      (@changed_cols);

            if (scalar(@changed_cols) != scalar(@values)) {
               no warnings 'uninitialized';
               my $mapping = join("\n", map { "  $_ => ".$class_object->property_for_column($_) } @changed_cols);
               Carp::croak("Column count mismatch while inserting into table $table_name_to_update.  "
                           . "The table metadata expects to see ".scalar(@changed_cols)
                           . " columns, but ".scalar(@values)." were retrieved from the object of type "
                           . $object_to_save->class . ".\nCurrent column => property mapping:\n$mapping\n"
                           . "There is probably a mismatch between the database column metadata and the column_name "
                           . "property metadata");
            }

            #grab fk_constraints so we can undef non primary-key nullable fks before delete
            my @non_pk_nullable_fk_columns = $self->get_non_primary_key_nullable_foreign_key_columns_for_table($table);

            if (@non_pk_nullable_fk_columns){
                my @insert_values;
                my %update_values;
                for (my $i = 0; $i < @changed_cols; $i++){
                    my $col = $changed_cols[$i];
                    if (grep {$col eq $_} @non_pk_nullable_fk_columns){
                        push @insert_values, undef;
                        $update_values{$col} = $values[$i];
                    }else{
                        push @insert_values, $values[$i];
                    }
                }

                push @commands, { type         => 'insert',
                                  table_name   => $table_name,
                                  column_names => \@changed_cols,
                                  sql          => $sql,
                                  params       => \@insert_values,
                                  class        => $table_class,
                                  id           => $id,
                                  dbh          => $data_source->get_default_dbh
                                };

                ##$DB::single = 1;
                my @pk_values = $self->_id_values_for_primary_key($table, $object_to_save);
                my $where = $self->_matching_where_clause($table, \@pk_values);
                
                my @update_cols = keys %update_values;
                my @update_values = ((map {$update_values{$_}} @update_cols), @pk_values);
                
                

                my $update_sql = " UPDATE ";
                $update_sql .= "${db_owner}." if ($db_owner);
                $update_sql .= "$table_name_to_update SET ". join(",", map { "$_ = ?" } @update_cols) . " WHERE $where";

                push @commands, { type         => 'update',
                                  table_name   => $table_name,
                                  column_names => \@update_cols,
                                  sql          => $update_sql,
                                  params       => \@update_values,
                                  class        => $table_class,
                                  id           => $id,
                                  dbh          => $data_source->get_default_dbh
                                };
            }
            else 
            {
                push @commands, { type         => 'insert',
                                  table_name   => $table_name,
                                  column_names => \@changed_cols,
                                  sql          => $sql,
                                  params       => \@values,
                                  class        => $table_class,
                                  id           => $id,
                                  dbh          => $data_source->get_default_dbh
                                };
            }

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

sub _generate_class_data_for_loading {
    my ($self, $class_meta) = @_;

    my $parent_class_data = $self->SUPER::_generate_class_data_for_loading($class_meta);

    my @class_hierarchy = ($class_meta->class_name,$class_meta->ancestry_class_names);
    my $order_by_columns;
    do {
        my @id_column_names;    
        for my $inheritance_class_name (@class_hierarchy) {
            my $inheritance_class_object = UR::Object::Type->get($inheritance_class_name);
            unless ($inheritance_class_object->table_name) {
                next;
            }
            @id_column_names =
                map { 
                    my $t = $inheritance_class_object->table_name;
                    ($t) = ($t =~ /(\S+)\s*$/); 
                    $t . '.' . $_ 
                }
                grep { defined }
                map { 
                    my $p = $inheritance_class_object->property_meta_for_name($_);
                    die ("No property $_ found for " . $inheritance_class_object->class_name . "?") unless $p;
                    $p->column_name;
                } 
                map { $_->property_name }
                grep { $_->column_name }
                $inheritance_class_object->direct_id_property_metas;

            last if (@id_column_names);
        }
        $order_by_columns = \@id_column_names;
    };

    my @all_table_properties;
    my @direct_table_properties;
    my $first_table_name;
    my $sub_classification_method_name;
    my ($sub_classification_meta_class_name, $subclassify_by);

    my @base_joins;
    my $prev_table_name;
    my $prev_id_column_name;

    for my $co ( $class_meta, @{ $parent_class_data->{parent_class_objects} } ) {   
        my $table_name = $co->table_name;
        next unless $table_name;

        $first_table_name ||= $co->table_name;
        $sub_classification_method_name ||= $co->sub_classification_method_name;
        $sub_classification_meta_class_name ||= $co->sub_classification_meta_class_name;
        $subclassify_by   ||= $co->subclassify_by;

        push @all_table_properties, 
            map { [$co, $_, $table_name, 0 ] }
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
        subclassify_by    => $subclassify_by,

        base_joins                          => \@base_joins,   
        order_by_columns                    => $order_by_columns,

        lob_column_names                    => \@lob_column_names,
        lob_column_positions                => \@lob_column_positions,

        query_config                        => $query_config,
        post_process_results_callback       => $post_process_results_callback,
    };

    return $class_data;
}
        
# We're overriding the method in UR::Object because we support 2 more
# event types: connect and query
sub validate_subscription {
    my ($self,$subscription_property) = @_;

    my $retval = $self->SUPER::validate_subscription(@_);
    return $retval if $retval;

    unless ( defined($subscription_property)
             and
             ( $subscription_property eq 'connect'
               or
               $subscription_property eq 'query'
             )
    ) {
        $subscription_property = '(undef)' unless defined ($subscription_property);
        Carp::croak("Unrecognized subscription aspect '$subscription_property'");
    }

    return 1;
}

sub _select_clause_for_table_property_data {
    my $self = shift;
    my $column_data = $self->_select_clause_columns_for_table_property_data(@_);
    my $select_clause = join(', ',@$column_data);
    return $select_clause;
}

sub _select_clause_columns_for_table_property_data {
    my $self = shift;

    my @column_data;
    for my $class_property (@_) {
        my ($sql_class,$sql_property,$sql_table_name) = @$class_property;
        $sql_table_name ||= $sql_class->table_name;
        my ($select_table_name) = ($sql_table_name =~ /(\S+)\s*$/s);

        # FIXME - maybe a better way would be for these sql-calculated properties, the column_name()
        # or maybe some other related property name) is actually calculated, so this logic
        # gets encapsulated in there?
        if (my $sql_function = $sql_property->calculate_sql) {
            my @calculate_from = ref($sql_property->calculate_from) eq 'ARRAY' ? @{$sql_property->calculate_from} : ( $sql_property->calculate_from );
            foreach my $sql_column_name ( @calculate_from ) {
                $sql_function =~ s/($sql_column_name)/$sql_table_name\.$1/g;
            }
            push(@column_data, $sql_function);
        } else {
            push(@column_data, $select_table_name . "." . $sql_property->column_name);
        }
    }
    return \@column_data;
}


# These seem to be standard for most RDBMSs
my %ur_data_type_for_vendor_data_type = (
     # DB type      UR Type
    'VARCHAR'          => ['Text', undef],
    'CHAR'             => ['Text', 1],
    'CHARACTER'        => ['Text', 1],
    'XML'              => ['Text', undef],

    'INTEGER'          => ['Integer', undef],
    'UNSIGNED INTEGER' => ['Integer', undef],
    'SIGNED INTEGER'   => ['Integer', undef],
    'INT'              => ['Integer', undef],
    'LONG'             => ['Integer', undef],
    'BIGINT'           => ['Integer', undef],
    'SMALLINT'         => ['Integer', undef],

    'FLOAT'            => ['Number', undef],
    'NUMBER'           => ['Number', undef],
    'DOUBLE'           => ['Number', undef],
    'DECIMAL'          => ['Number', undef],
    'REAL'             => ['Number', undef],

    'BOOL'             => ['Boolean', undef],
    'BOOLEAN'          => ['Boolean', undef],
    'BIT'              => ['Boolean', undef],

    'DATE'             => ['DateTime', undef],
    'DATETIME'         => ['DateTime', undef],
    'TIMESTAMP'        => ['DateTime', undef],
    'TIME'             => ['DateTime', undef],
);

sub ur_data_type_for_data_source_data_type {
    my($class,$type) = @_;

    my $urtype = $ur_data_type_for_vendor_data_type{uc($type)};
    unless (defined $urtype) {
        $urtype = $class->SUPER::ur_data_type_for_data_source_data_type($type);
    }
    return $urtype;
}


1;

=pod

=head1 NAME

UR::DataSource::RDBMS - Abstract base class for RDBMS-type data sources

=head1 DESCRIPTION

This class implements the interface UR uses to query RDBMS databases with
DBI.  It encapsulates the system's knowledge of classes/properties relation
to tables/columns, and how to generate SQL to create, retrieve, update and
delete table rows that represent object instances.

=head1 SEE ALSO

UR::DataSource, UR::DataSource::Oracle, UR::DataSource::Pg, UR::DataSource::SQLite
UR::DataSource::MySQL

=cut
