package Command;

use strict;
use warnings;
use UR;

our $VERSION = "0.41_04"; # UR $VERSION;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is_abstract => 1,
    subclassify_by_version => 1,
);

1;
