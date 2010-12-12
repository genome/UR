package UR::Namespace::Command::Init;
use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "Command",
    has => [
        namespace => {
            is => 'Text',
            shell_args_position => 1,
            doc => 'create this namespace'
        },
        db => {
            is => 'Text',
            is_optional => 1,
            shell_args_position => 2,
            is_many => 1,
            doc => 'DBI connection string for the primary data source',
        },
    ],
    doc => 'initialize a new UR app in one command',
);

sub sub_command_sort_position { 1 }

sub execute {
    my $self = shift;

    $self->status_message(">> ur define namespace " . $self->namespace);
    UR::Namespace::Command::Define::Namespace->execute(nsname => $self->namespace) or return;

    chdir $self->namespace or ($self->error_message("error changing to namespace dir? $!") and return);
   
    $self->status_message(">> ur define datasource " . $self->db);
    UR::Namespace::Command::Define::DataSource->execute(dbid => $self->db_dsn) or return;

    return 1; 
}

1;

