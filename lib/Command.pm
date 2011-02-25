package Command;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is_abstract => 1,
    use_parallel_versions => 1,
);

1;
