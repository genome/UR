package URT::TestRole;

use strict;
use warnings;

role URT::TestRole {
    has => [ 'role_param' ],
    requires => [ 'required_class_param', 'required_class_method' ],
};

sub role_method { 1 }

1;
