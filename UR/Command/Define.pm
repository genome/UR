
# The diff command delegates to sub-commands under the adjoining directory.

package UR::Command::Define;

use warnings;
use strict;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Command',
);

sub help_brief { "Add logical entities to a namespace." }

sub shell_args_description { "[namespace|...]"; }

1;
