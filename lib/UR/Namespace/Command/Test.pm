
# The diff command delegates to sub-commands under the adjoining directory.

package UR::Namespace::Command::Test;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Namespace::Command",
);

sub help_brief {
   "Perform various tests."
}

1;

