package UR::Command::Define::Datasource::RDBMS;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command",
    is_abstract => 1,
    has => [
                name => {
                        type => 'String',
                        is_optional => 1,
                        doc => "The name to give this data source. The default is the same name as the namespace",
                        default => 'Main',
                },
                server => { 
                        type => 'String',
                        is_optional => 1,
                        doc => 'The hostname where the database lives (if required)',
                },
                login => {
                        type => 'String',
                        is_optional => 1,
                        doc => 'The login name to be used for this data source (if one is required)',
                },
                password => {
                        type => 'String',
                        is_optional => 1,
                        doc => 'The password to be used for this data source (if one is required)',
                },
                schema => {
                        type => 'String',
                        is_optional => 1,
                        doc => 'The schema name (sometimes called owner) to be used for this data source (if one is required)',
                },
                connect => {
                        is => 'String',
                        is_optional => 1,
                        doc => 'The connection string used by DBI.'
                }      
           ],
);

sub help_description {
   "Write a new UR::DataSource subclass module for the current namespace."
}

sub _type {
    my $self = shift;
    my ($type) = ($self->class =~ /([^:]+)$/);
    return $type;
}

sub _data_source_sub_class_name {
    my $self = shift;
    my $type = $self->_type;
    return "UR::DataSource::" . $type;
}

# REFACTOR INTO SUBCLASSES
sub _server_adjusted {
    my $self = shift;
    my $lc_type = lc($self->_type);
    my $server;
    if ($lc_type eq 'oracle') {
        $server = sprintf("'%s'", $self->server);
    }
    elsif ($lc_type eq 'sqlite') {
        $server = "''";
    }
    else {
        $server = sprintf("'dbname=%s;host=%s'", lc $self->name, $self->server);
    }
    return $server;
}

# REFACTOR INTO SUBCLASSES
sub _db_name_adjusted {
    my $self = shift;
    my $db_name_src = '';
    if (lc $self->_type eq 'mysql') {
        $db_name_src = sprintf(q('%s'), $self->name);
    }
    return $db_name_src;
}

# REFACTOR INTO SUBCLASSES
sub _schema_adjusted {
    my $self = shift;
    my $schema = $self->schema;
    if ($schema) {
        $schema = qq('$schema');
    } else {
        if (lc($self->_type) eq 'postgresql') {
            $schema = qq('public');
        } elsif (lc($self->_type) eq 'mysql') {
            $schema = 'undef';
        } else {
            $schema = qq('');
        }
    }
    return $schema;
}

sub _write_name { 0 }

sub _write_server { 1 }

sub _write_login { 1 }

sub _write_auth  { 1 } 

sub _write_owner { 1 }

sub validate_params {
    my $self = shift;
    if ($self->bare_args) {
        $self->error_message("Unexpected arguments!");
        return;
    }
    return 1;
}

sub execute {
    my $self = shift;

    my $namespace = $self->namespace_name;
    unless ($namespace) {
        $self->error_message("This command must be run from a namespace directory.");
        return;
    }

    my $type = $self->_type();
    my $ds_type = $self->_data_source_sub_class_name();

    $self->name("main") unless ($self->name);

    my $name = ucfirst($self->name);

    mkdir('DataSource') unless (-d 'DataSource');

    my $ds_class = $namespace . '::DataSource::' . $name;
    my $ds = UR::Object::Type->define(
        class_name => $ds_class,
        is => [$ds_type],
        is_abstract => 0, 
    );
    unless ($ds) {
        $self->error_message("Failed to define new DataSource class $ds_class");
        return;
    }  
    my $src = $ds->resolve_module_header_source;
    my $filename = 'DataSource/'.$name.'.pm';
    my $fh = IO::File->new("> $filename");
    unless ($fh) {
        $self->error_message("Can't open $filename for writing: $!");
        return;
    }

    $fh->print(qq(
use strict;
use warnings;

package $ds_class;

use $namespace;

$src
    ));

    if ($self->_write_server) {
        my $server = $self->_server_adjusted();

        $fh->print(qq|
# This becomes the third part of the colon-separated data_source
# string passed to DBI->connect()
sub server {
    $server;
}
        |);
    }


    if ($self->_write_name) {
        my $db_name = $self->_db_name_adjusted();
        $fh->print(qq(
# Name of the database
sub db_name {
    $db_name;
}
        ));
    }

    if ($self->_write_owner) {
        my $schema = $self->_schema_adjusted();
        $fh->print(qq(
# This becomes the schema argument to most of the data dictionary methods
# of DBI like table_info, column_info, etc.
sub owner {
    $schema;
}
        ));
    }

    if ($self->_write_login) {
        my $login = sprintf("'%s'", $self->login);
        $fh->print(qq(
# This becomes the username argument to DBI->connect
sub login {
    $login;
}
        ));
    }

    if ($self->_write_auth) {
        my $password = sprintf("'%s'", $self->password);
        $fh->print(qq(
# This becomes the password argument to DBI->connect
sub auth {
    $password;
}
        ));
    }

    if ($self->can("_module_tail")) {
        $fh->print($self->_module_tail);
    }

    $fh->print("\n1;\n");

    $self->status_message("A   $ds_class ($ds_type)\n");

    $self->status_message("    ...connecting...\n");

    my $dbh = $ds_class->get_default_dbh();
    if ($dbh) {
        $self->status_message("    ....ok\n");
    }
    else {
        $self->error_message("    ERROR: " . $ds_class->error_message);
    }
    return 1;
};

1;

