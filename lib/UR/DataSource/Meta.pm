package UR::DataSource::Meta;

# The datasource for metadata describing the tables, columns and foreign
# keys in the target datasource

use strict;
use warnings;

use UR;
our $VERSION = "0.30"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::DataSource::Meta',
    is => ['UR::DataSource::SQLite'],
);

# Do a DB dump at commit time
sub dump_on_commit { 1; }

sub _resolve_class_name_for_table_name_fixups {
    my $self = shift->_singleton_object;

    if ($_[0] =~ m/Dd/) {
        $_[0] = "DataSource::RDBMS::";
    }

    return @_;
}

# NOTE: When you change this, also change the value in $METADATA_DB_SQL below
sub CURRENT_METADB_VERSION { 2 };

sub _init_created_dbh {
    my($self,$dbh) = @_;

    my $ver = $self->_get_current_schema_version($dbh);
    my $latest_ver = $self->CURRENT_METADB_VERSION;

    my $class = $self->class;
    if (! defined($ver) or $ver < $latest_ver) {
        no warnings 'uninitialized';
        Carp::croak("Your MetaDB for $class has an out of date schema.  It is version $ver, while the latest is version $latest_ver.\nPlease run the command 'ur update meta-db-schema $class` to update it");
    } elsif ($ver > $latest_ver) {
        Carp::croak("Your MetaDB for $class is newer than expected.  It is version $ver, while this UR understands version $latest_ver");
    }

    return $dbh;
}


sub _get_current_schema_version {
    my($self,$dbh) = @_;

    my $raiseerror = $dbh->{'RaiseError'};
    my $printerror = $dbh->{'PrintError'};
    my $handleerror = $dbh->{'HandleError'};

    $dbh->{'RaiseError'} = 0;
    $dbh->{'PrintError'} = 0;
    $dbh->{'HandleError'} = undef;

    my @row = eval { $dbh->selectrow_array("select value from dd_meta_settings where key = 'ur_metadb_version'") };

    $dbh->{'RaiseError'} = $raiseerror;
    $dbh->{'PrintError'} = $printerror;
    $dbh->{'HandleError'} = $handleerror;

    if (!@row) {
        # There were actually 2 versions that don't have the settings table
        if ($self->server =~ m/\.sqlite3n$/) {
            return 1;
        } else {
            return 0;
        }
    }

    return $row[0];
}



sub _update_schema_for_version_0 {
    my($self,$dbh) = @_;

    # Nothing really to do here...
    # This is got DBD::SQLite earlier than 1.26_04
    # which return NULL for the 'owner' field in schema introspection
    return 1;
}

sub _update_schema_for_version_1 {
    my($self,$dbh) = @_;

    # DBD::SQLite after 1.26_04 starts reporting 'main' for the default database instead of
    # the empty string or NULL.  We'll change the code in UR::DataSource::SQLite so it always
    # returns main if you're on an old version
    foreach my $table_name (qw( dd_table dd_table_column dd_fk_constraint dd_fk_constraint_column
                                dd_bitmap_index dd_pk_constraint_column dd_unique_constraint_column ) )
    {
        unless ($dbh->do("update $table_name set owner = 'main' where owner is null")) {
            Carp::croak("Can't update 'owner' column for table $table_name: ".$dbh->errstr);
        }
    }

    # dd_fk_constraint has r_owner, too
    unless ($dbh->do("update dd_fk_constraint set r_owner = 'main' where owner is null")) {
        Carp::croak("Can't update 'r_owner' column for table dd_fk_constraint: ".$dbh->errstr);
    }

    # And now we actually track the version
    unless ($dbh->do("CREATE TABLE dd_meta_settings (key varchar NOT NULL, value varchar NOT NULL, PRIMARY KEY (key,value))")) {
        Carp::croak("Can't create table dd_meta_settings: ".$dbh->errstr);
    }
    unless ($dbh->do("INSERT INTO dd_meta_settings VALUES ('ur_metadb_version',2)")) {
        Carp::croak("Can't insert into dd_meta_settings: ".$dbh->errstr);
    }

    return 2;
}


# This is the template for the schema:
our $METADATA_DB_SQL =<<EOS;
CREATE TABLE IF NOT EXISTS dd_bitmap_index (
    data_source varchar NOT NULL,
    owner varchar,
    table_name varchar NOT NULL,
    bitmap_index_name varchar NOT NULL,
    PRIMARY KEY (data_source, owner, table_name, bitmap_index_name)
);
CREATE TABLE IF NOT EXISTS dd_fk_constraint (
    data_source varchar NOT NULL,
    owner varchar,
    r_owner varchar,
    table_name varchar NOT NULL,
    r_table_name varchar NOT NULL,
    fk_constraint_name varchar NOT NULL,
    last_object_revision timestamp NOT NULL,
    PRIMARY KEY(data_source, owner, r_owner, table_name, r_table_name, fk_constraint_name)
);
CREATE TABLE IF NOT EXISTS dd_fk_constraint_column (
    fk_constraint_name varchar NOT NULL,
    data_source varchar NOT NULL,
    owner varchar,
    table_name varchar NOT NULL,
    r_table_name varchar NOT NULL,
    column_name varchar NOT NULL,
    r_column_name varchar NOT NULL,

    PRIMARY KEY(data_source, owner, table_name, fk_constraint_name, column_name)
);
CREATE TABLE IF NOT EXISTS dd_pk_constraint_column (
    data_source varchar NOT NULL,
    owner varchar,
    table_name varchar NOT NULL,
    column_name varchar NOT NULL,
    rank integer NOT NULL,
    PRIMARY KEY (data_source,owner,table_name,column_name,rank)
);
CREATE TABLE IF NOT EXISTS dd_table (
     data_source varchar NOT NULL,
     owner varchar,
     table_name varchar NOT NULL,
     table_type varchar NOT NULL,
     er_type varchar NOT NULL,
     last_ddl_time timestamp,
     last_object_revision timestamp NOT NULL,
     remarks varchar,
     PRIMARY KEY(data_source, owner, table_name)
);
CREATE TABLE IF NOT EXISTS dd_table_column (
    data_source varchar NOT NULL,
    owner varchar,
    table_name varchar NOT NULL,
    column_name varchar NOT NULL,
    data_type varchar NOT NULL,
    data_length varchar,
    nullable varchar NOT NULL,
    last_object_revision timestamp NOT NULL,
    remarks varchar,
    PRIMARY KEY(data_source, owner, table_name, column_name)
);
CREATE TABLE IF NOT EXISTS dd_unique_constraint_column (
    data_source varchar NOT NULL,
    owner varchar,
    table_name varchar NOT NULL,
    constraint_name varchar NOT NULL,
    column_name varchar NOT NULL,
    PRIMARY KEY (data_source,owner,table_name,constraint_name,column_name)
);
CREATE TABLE IF NOT EXISTS dd_meta_settings (
    key varchar NOT NULL,
    value varchar NOT NULL,
    PRIMARY KEY (key,value)
);
INSERT INTO dd_meta_settings VALUES ('ur_metadb_version',2);
EOS

our $module_template=<<EOS;
package %s;

use warnings;
use strict;

use UR;

%s

1;
EOS

# This is a bit ugly until the db cache is symmetrical with the other transactional stuff
# It is run by the "ur update schema" command 
sub generate_for_namespace {
    my $class = shift;
    my $namespace_name = shift;
    
    Carp::confess('Refusing to make MetaDB for the UR namespace') if $namespace_name eq 'UR';

    my $namespace_path = $namespace_name->__meta__->module_path();

    my $meta_datasource_name = $namespace_name . '::DataSource::Meta';
    my $meta_datasource = UR::Object::Type->define(
        class_name => $meta_datasource_name, 
        is => 'UR::DataSource::Meta',
        is_abstract => 0,
    );
    my $meta_datasource_src = $meta_datasource->resolve_module_header_source();
    my $meta_datasource_filename = $meta_datasource->module_base_name();

    my $meta_datasource_filepath = $namespace_path;
    return unless defined($meta_datasource_filepath);  # This namespace could be fabricated at runtime

    $meta_datasource_filepath =~ s/.pm//;
    $meta_datasource_filepath .= '/DataSource';
    mkdir($meta_datasource_filepath);
    unless (-d $meta_datasource_filepath) {
        die "Failed to create directory $meta_datasource_filepath: $!";
    } 
    $meta_datasource_filepath .= '/Meta.pm';
 
    # Write the Meta DB datasource Module
    if (-e $meta_datasource_filepath) {
        Carp::croak("Can't create new MetaDB datasource Module $meta_datasource_filepath: File already exists");
    }
    my $fh = IO::File->new("> $meta_datasource_filepath");
    unless ($fh) {
        Carp::croak("Can't create MetaDB datasource Module $meta_datasource_filepath: $!");
    }
    $fh->printf($module_template, $meta_datasource_name, $meta_datasource_src);

    # Write the skeleton SQLite file
    my $meta_db_file = $meta_datasource->class_name->_data_dump_path;
    IO::File->new($meta_db_file,'w')->print($UR::DataSource::Meta::METADATA_DB_SQL);

    my $meta_schema_file = $meta_datasource->class_name->_schema_path;
    IO::File->new($meta_schema_file,'w')->print($UR::DataSource::Meta::METADATA_DB_SQL);
    
    return ($meta_datasource, $meta_db_file, $meta_schema_file);
}

1;

=pod

=head1 NAME

UR::DataSource::Meta - Data source for the MetaDB

=head1 SYNOPSIS

  my $meta_table = UR::DataSource::RDBMS::Table->get(
                       table_name => 'DD_TABLE'
                       namespace => 'UR',
                   );

  my @myapp_tables = UR::DataSource::RDBMS::Table->get(
                       namespace => 'MyApp',
                   );

=head1 DESCRIPTION

UR::DataSource::Meta a datasource that contains all table/column meta
data for the UR namespace itself.  Essentially the schema schema.

=head1 INHERITANCE

UR::DataSource::Meta is a subclass of L<UR::DataSource::SQLite>

=head1 get() required parameters

C<namespace> or C<data_source> are required parameters when calling C<get()>
on any MetaDB-sourced object types.

=cut
