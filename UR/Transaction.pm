
package UR::Transaction;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Context::Transaction',
);

1;