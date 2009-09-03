
# The diff command delegates to sub-commands under the adjoining directory.

package UR::Namespace::Command::Update;

use warnings;
use strict;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Namespace::Command",
);

sub help_brief {
   "Update different elements of the UR system";
}

1;

