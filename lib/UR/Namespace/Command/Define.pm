package UR::Namespace::Command::Define;

use warnings;
use strict;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command',
    doc => "define namespaces, data sources and classes",
);

sub sub_command_sort_position { 2 }

sub shell_args_description { "[namespace|...]"; }

1;

