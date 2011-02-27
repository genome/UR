package Command;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is_abstract => 1,
    subclassify_by_version => 1,
);

1;
