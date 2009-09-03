

package UR::Namespace::Command::Define::Namespace;

use strict;
use warnings;
use UR;
use IO::File;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "Command",
);

sub sub_command_sort_position { 1 }

sub help_brief {
   "Write a new namespace module."
}

our $module_template=<<EOS;
package %s;

use warnings;
use strict;

use UR;

%s

1;
EOS


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
    owner varchar NOT NULL,
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
EOS



# FIXME This should be refactored at some point to act more like "update classes" in that it
# Creates a bunch of objects and them uses the change log to determine what is new and what 
# files to create/write
sub execute {
    my $self = shift;
    
    my $name_array = $self->bare_args;
    unless ($name_array) {
        $self->error_message("No name specified!");
        return;
    }
    if (@$name_array < 1) {
        $self->error_message("Please supply a namespace name.");
        return;
    }
    for my $name (@$name_array) {
        if (-e $name . ".pm") {
            $self->error_message("Module ${name}.pm already exists!");
            return;
        }
        eval "package $name;";
        if ($@) {
            $self->error_message("Invalid package name $name: $@");
            return;
        }


        # Step 1 - Make a new Namespace
        my $namespace = UR::Object::Type->define(class_name => $name,
                                                 is => ['UR::Namespace'],
                                                 is_abstract => 0);
        my $namespace_src = $namespace->resolve_module_header_source;


        # Step 2 - Make a new Meta DataSource 
        my $meta_datasource_name = $name . '::DataSource::Meta';
        my $meta_datasource = UR::Object::Type->define(
            class_name => $meta_datasource_name, 
            is => 'UR::DataSource::Meta',
            is_abstract => 0,
        );
        my $meta_datasource_src = $meta_datasource->resolve_module_header_source();
        my $meta_datasource_filename = $meta_datasource->module_base_name();

        # Step 3 - Make an empty Vocabulary
        my $vocab_name = $name->get_vocabulary();
        my $vocab = UR::Object::Type->define(
            class_name => $vocab_name,
            is => 'UR::Vocabulary',
            is_abstract => 0,
        );
        my $vocab_src = $vocab->resolve_module_header_source();
        my $vocab_filename = $vocab->module_base_name();

        

        # At this point, all the objects/types are created.  Go ahead and make files
        # on the filesystem.

        # write the namespace module
        $self->status_message("A   $name (UR::Namespace)\n");
        IO::File->new("> $name.pm")->printf($module_template, $name, $namespace_src);

        # Write the vocbaulary module
        mkdir($name);
        IO::File->new("> $vocab_filename")->printf($module_template, $vocab_name, $vocab_src);
        $self->status_message("A   $vocab_name (UR::Vocabulary)\n");

        # Write the Meta DB datasource
        mkdir($name . '/DataSource/');
        IO::File->new("> $meta_datasource_filename")->printf($module_template, $meta_datasource_name, $meta_datasource_src);
        $self->status_message("A   $meta_datasource_name (UR::DataSource::Meta)\n");

        # And finally, the SQL source for a new, empty metadata DB
        my $meta_db_file = $self->create_meta_db_skeleton($meta_datasource);
        $self->status_message("A   $meta_db_file (Metadata DB skeleton)");

    }
    return 1; 
}


sub create_meta_db_skeleton {
    my($self,$meta_datasource) = @_;

    unless (ref $meta_datasource) {
        $meta_datasource = $meta_datasource->get_class_object;
    }

    my $meta_db_file = $meta_datasource->class_name->_data_dump_path;
    IO::File->new(">$meta_db_file")->print($METADATA_DB_SQL);
    return $meta_db_file;
}


1;

