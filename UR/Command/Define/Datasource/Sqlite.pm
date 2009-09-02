package UR::Command::Define::Datasource::Sqlite;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command::Define::Datasource::RDBMS",
    has => [
        file    => { is => 'FilePath', is_optional => 1 }
    ]
);

sub help_brief {
   "Add a SQLite data source to the current namespace."
}

sub _write_server  { 0 }

sub _write_login  { 0 }

sub _write_auth   { 0 }

sub _write_db_name { 0 }

sub _write_owner  { 0 }

sub _data_source_sub_class_name {
    "UR::DataSource::SQLite"
}

sub _module_tail {  
    my $self = shift;
    my $file_path = $self->file;
    return unless $file_path and length($file_path);
    return <<EOS

sub _database_file_path {
    return '$file_path';
}

EOS
}

1;

