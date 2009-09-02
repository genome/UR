package UR::Command::Define::Datasource::Postgresql;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command::Define::Datasource::RDBMS",
);

sub help_brief {
   "Add a PostgreSQL data source to the current namespace."
}

sub _write_dbname { 1 }

sub _data_source_sub_class_name {
    "UR::DataSource::PostgreSQL"
}

1;

