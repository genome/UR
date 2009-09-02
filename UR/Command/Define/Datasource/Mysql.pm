package UR::Command::Define::Datasource::Mysql;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command::Define::Datasource::RDBMS",
);

sub help_brief {
   "Add a MySQL data source to the current namespace."
}

sub _data_source_sub_class_name {
    "UR::DataSource::MySQL"
} 

# db_name must be provided on the mysql datasource adapter
sub _write_name {1;}

sub execute {
    my $self = shift;

    $self->error_message("postponed until later, use 'ur define datasource rdbms' for now");
    return 0;
}


1;

