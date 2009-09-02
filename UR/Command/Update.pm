
# The diff command delegates to sub-commands under the adjoining directory.

package UR::Command::Update;

use warnings;
use strict;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command",
);

sub help_brief {
   "Update different elements of the UR system";
}

1;

