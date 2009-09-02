package UR::Command::Define::Datasource::Oracle;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command::Define::Datasource::RDBMS",
);

sub help_brief {
   "Add an Oracle data source to the current namespace."
}

1;

