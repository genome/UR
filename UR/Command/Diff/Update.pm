
package UR::Command::Diff::Update;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command",
);

sub help_description { 
    "Show the differences between class schema and database schema."
}

*for_each_class_object = \&UR::Command::Diff::for_each_class_object_delegate_used_by_sub_commands;

1;
