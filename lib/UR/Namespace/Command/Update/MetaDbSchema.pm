
package UR::Namespace::Command::Update::MetaDbSchema;

use strict;
use warnings;
use UR;
our $VERSION = "0.30"; # UR $VERSION;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command::Base',
    has => [
        data_source_name => { is => 'Text', shell_args_position => 1, doc => 'Data source class name to update'},
    ],
);

sub sub_command_sort_position { 5 };

sub help_brief {
    "Update Metadata database schema to the current version";
}

sub help_detail {
    return <<EOS;

When the schema for a Namespace's metadata database changes, this command
will migrate the data from an older schema to the latest schema.

Metadata database schemas very rarely change.  It's version can only
change when UR is updated.  When an update is required, attempting
to connect to the Metadata database will generate an exception.

EOS
}



sub execute {
    my $self = shift;

    $self->_init;

    my $namespace = $self->namespace_name;
    unless ($namespace) {
        $self->error_message("This command must be run from a namespace directory.");
        return;
    }

    my $data_source_name = $self->data_source_name;
    my $ds_name = eval { $data_source_name->class };
    unless ($ds_name eq $data_source_name) {
        $self->error_message("There was a problem loading the class $data_source_name: $@");
        return;
    }

    my $ds_meta = $data_source_name->__meta__;
    unless ($ds_meta) { 
        $self->error_message("There was a problem loading the class $data_source_name");
        $self->error_message("Could not find class metadata for class $data_source_name");
    }
    unless ($data_source_name->isa('UR::DataSource::Meta')) {
        $self->error_message("There was a problem loading the class $data_source_name");
        $self->error_message("Data source $data_source_name is not a decendant of UR::DataSource::Meta, and therefore not a metadata database");
        return;
    }

    # We need to temporarily replace _init_created_dbh because it's going to try and throw an
    # exception when it's out of date.  This one just returns the dbh right back
    { no warnings 'redefine';
      *UR::DataSource::Meta::_init_created_dbh = sub { return $_[1] };
    }

    my $ds_obj;
    if ($data_source_name->isa('UR::Singleton')) {
        $ds_obj = $data_source_name->_singleton_object;
    } else {
        Carp::croak("Data source $data_source_name is not a singleton class");
    }

    $self->status_message("Updating metadata database $data_source_name in namespace $namespace\n");

    my $dbh = $data_source_name->get_default_handle;
    my $current_ver = $data_source_name->_get_current_schema_version($dbh) || 0;
    my $latest_ver = $data_source_name->CURRENT_METADB_VERSION;
    $self->status_message("Current metaDB schema is version $current_ver, updating to $latest_ver");

    while ($current_ver < $latest_ver) {
        my $update_method = '_update_schema_for_version_' . $current_ver;
        my $next_ver = $ds_obj->$update_method($dbh);
        if ($next_ver <= $current_ver) {
            Carp::croak("Method '$update_method' of class $data_source_name did not increment the version number");
        }
        $current_ver = $next_ver;
        $self->status_message("Updated to version $current_ver");
    }

    unless ($dbh->do("update dd_meta_settings set value = '$current_ver' where key = 'ur_metadb_version'")) {
        Carp::croak("Can't update schema versioning info: ".$dbh->errstr);
    }
    $self->status_message("Successfully updated $data_source_name to version $current_ver");
    return 1;
}

1;

