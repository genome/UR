
# The diff command delegates to sub-commands under the adjoining directory.

package UR::Command::List;

use warnings;
use strict;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command",
);

sub help_brief {
   "List various types of things." 
}

1;

