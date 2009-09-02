
# The diff command delegates to sub-commands under the adjoining directory.

package UR::Command::Define::Datasource;

use warnings;
use strict;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command",
);

sub help_brief {
   "Add a data source to the current namespace.";
}

1;

