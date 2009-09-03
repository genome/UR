
package UR::Namespace::Command::Rename;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Namespace::Command",
);

sub help_brief {
    "Rename logical schema elements."
}

1;

