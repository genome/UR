package UR::Namespace::Command::Export;

use warnings;
use strict;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command',
);

sub help_brief { "Add logical entities to a namespace." }

sub shell_args_description { "[namespace|...]"; }

1;

