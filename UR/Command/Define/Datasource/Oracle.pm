package UR::Command::Define::Datasource::Oracle;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command::Define::Datasource::Rdbms",
);

sub help_brief {
   "Add an Oracle data source to the current namespace."
}

sub execute {
    my $self = shift;

    $self->error_message("postponed until later, use 'ur define datasource rdbms' for now");
    return 0;
}


1;

