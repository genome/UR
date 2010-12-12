package UR::Namespace::Command::Update;
use warnings;
use strict;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Namespace::Command",
    doc => 'update parts of the source tree of a UR namespace'
);

sub sub_command_sort_position { 4 }

1;

