package UR::Command::Define::Datasource::Rdbms;

use strict;
use warnings;
use UR;

use IO::File;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command",
    has => [
                dsname => {
                        type => 'String',
                        doc => "The name to give this data source. The default is the same name as the namespace",
                        #default => 'Main',  # FIXME - default dosen't seem to work.  It's _always_ 'Main' even if you give --name on the cmdline
                        is_optional => 1,
                },
                dsn => {
                        is => 'String',
                        doc => 'The connection string used by DBI.'
                },
                # When it's refactored into subclasses, only some will need these
                login => {   
                        is => 'String',
                        doc => 'User to log in with',
                        is_optional => 1,   
                },
                auth => {
                        is => 'String',
                        doc => 'Password to log in with',
                        is_optional => 1,
                },
                # FIXME is there a way to make owner and schema be the same?
                owner => {
                        is => 'String',
                        doc => 'Owner/schema to connect to',
                        is_optional => 1,
                },
                schema => {
                        is => 'String',
                        doc => 'Owner/schema to connect to',
                        is_optional => 1,
                },
           ],
);

sub help_description {
   "Define a UR datasource connected to a relational database through DBI";
}


sub _decompose_dsn {
    my($self,$dsn) = @_;

    #my($dbi,$driver,$db_string) = split(/:/, $dsn, 3);
    return split(/:/, $dsn, 3);
}



#sub _type {
#    my $self = shift;
#    my ($type) = ($self->class =~ /([^:]+)$/);
#    return $type;
#}
#
#sub _data_source_sub_class_name {
#    my $self = shift;
#    my $driver = shift;
#    return "UR::DataSource::" . $driver;
#}
#
## REFACTOR INTO SUBCLASSES
#sub _server_adjusted {
#    my $self = shift;
#    my $lc_type = lc($self->_type);
#    my $server;
#    if ($lc_type eq 'oracle') {
#        $server = sprintf("'%s'", $self->server);
#    }
#    elsif ($lc_type eq 'sqlite') {
#        $server = "''";
#    }
#    else {
#        $server = sprintf("'dbname=%s;host=%s'", lc $self->name, $self->server);
#    }
#    return $server;
#}
#
## REFACTOR INTO SUBCLASSES
#sub _db_name_adjusted {
#    my $self = shift;
#    my $db_name_src = '';
#    if (lc $self->_type eq 'mysql') {
#        $db_name_src = sprintf(q('%s'), $self->name);
#    }
#    return $db_name_src;
#}
#
## REFACTOR INTO SUBCLASSES
#sub _schema_adjusted {
#    my $self = shift;
#    my $schema = $self->schema;
#    if ($schema) {
#        $schema = qq('$schema');
#    } else {
#        if (lc($self->_type) eq 'postgresql') {
#            $schema = qq('public');
#        } elsif (lc($self->_type) eq 'mysql') {
#            $schema = 'undef';
#        } else {
#            $schema = qq('');
#        }
#    }
#    return $schema;
#}
#
#sub _write_name { 0 }
#
#sub _write_server { 1 }
#
#sub _write_login { 1 }
#
#sub _write_auth  { 1 } 
#
#sub _write_owner { 1 }

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
$DB::single=1;
    # FIXME strange... the eval here loads the right module but $@ contains "Compilation error"
    # my $ret = eval "use above $namespace; print qq(Hi $@\n);";
    my $ret = above::use_package($namespace);
    if ($@) {
        $self->error_message("Can't load namespace $namespace: $@");
        return;
    }

    my(undef,$driver,$connect) = $self->_decompose_dsn($self->dsn);
    unless ($driver && $connect) {
        $self->error_message("Couldn't determine DBI driver and database string from dsn ".$self->dsn);
        return;
    }

    # FIXME see the comment in the class definition about default values
    my $name = ucfirst($self->dsname) || 'Main';

    my $this_ds_class = $namespace . '::DataSource::' . $name;
    my $this_ds_parent_class = 'UR::DataSource::'.$driver;

    if (eval {$this_ds_class->get_class_object}) {
        $this_ds_class =~ s/::/\//g;
        $self->error_message("A datasource already exists by that name in module ".$INC{$this_ds_class . '.pm'});
        return;
    }
    

    # Figure out the right path the Datasource goes in
    my $namespace_module = $namespace . '.pm';
    unless ($INC{$namespace_module}) {
        $self->error_message("Namespace $namespace has no entry in %INC!?");
        return;
    }

    my $path = $INC{$namespace_module};
    ($path) = ($path =~ m/^(.*)\.pm/);
    $path .= '/DataSource/';

    my $module_pathname = $path . $name . '.pm';

    mkdir $path;
    unless (-d $path) {
        $self->error_message("Can't create data source directory $path: $!");
        return;
    }


    my $ds = UR::Object::Type->define(
        class_name => $this_ds_class,
        is => [$this_ds_parent_class],
        is_abstract => 0, 
    );
    unless ($ds) {
        $self->error_message("Failed to define new DataSource class $this_ds_class");
        return;
    }  
    my $src = qq(use strict;\nuse warnings;\n\npackage $this_ds_class;\n\nuse $namespace;\n\n);
    $src .= $ds->resolve_module_header_source . "\n\n";


    if ($self->login) {
        my $login = $self->login;
        $src .= qq(sub login {\n    "$login";}\n\n);
    }

    if ($self->auth) {
        my $auth = $self->auth;
        $src .= qq(sub auth {\n    "$auth";}\n\n);
    }

    if ($self->owner || $self->schema) {
        my $owner = $self->owner || $self->schema;
        $src .= qq(sub owner {\n    "$owner";}\n\n);
    }

    $src .= "\n1;\n";

    my $fh = IO::File->new(">$module_pathname");
    unless ($fh) {
        $self->error_message("Can't open $module_pathname for writing: $!");
        return;
    }

    $fh->print($src);
    $fh->close();

#    if ($self->_write_server) {
#        my $server = $self->_server_adjusted();
#
#        $fh->print(qq|
## This becomes the third part of the colon-separated data_source
## string passed to DBI->connect()
#sub server {
#    $server;
#}
#        |);
#    }
#
#
#    if ($self->_write_name) {
#        my $db_name = $self->_db_name_adjusted();
#        $fh->print(qq(
## Name of the database
#sub db_name {
#    $db_name;
#}
#        ));
#    }
#
#    if ($self->_write_owner) {
#        my $schema = $self->_schema_adjusted();
#        $fh->print(qq(
## This becomes the schema argument to most of the data dictionary methods
## of DBI like table_info, column_info, etc.
#sub owner {
#    $schema;
#}
#        ));
#    }
#
#    if ($self->_write_login) {
#        my $login = sprintf("'%s'", $self->login);
#        $fh->print(qq(
## This becomes the username argument to DBI->connect
#sub login {
#    $login;
#}
#        ));
#    }
#
#    if ($self->_write_auth) {
#        my $password = sprintf("'%s'", $self->password);
#        $fh->print(qq(
## This becomes the password argument to DBI->connect
#sub auth {
#    $password;
#}
#        ));
#    }
#
#    if ($self->can("_module_tail")) {
#        $fh->print($self->_module_tail);
#    }
#
#    $fh->print("\n1;\n");

    $self->status_message("A   $this_ds_class ($this_ds_parent_class)\n");

    # FIXME when this is split back out into subclasses for each type of DS,
    # then this goes into the SQLite class
    if ($driver eq 'SQLite') {
        # Create a new, empty DB if it dosen't exist yet
        $module_pathname =~ s/\.pm$/.sqlite3/;
        IO::File->new($module_pathname, O_WRONLY | O_CREAT);
    }

    $self->status_message("    ...connecting...");

    my $dbh = $this_ds_class->get_default_dbh();
    if ($dbh) {
        $self->status_message("    ....ok\n");
    }
    else {
        $self->error_message("    ERROR: " . $this_ds_class->error_message);
    }
    return 1;
};

1;

