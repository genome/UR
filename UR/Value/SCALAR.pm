package UR::Value::SCALAR;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Value::SCALAR',
    is => ['UR::Value'],
);

1;
#$Header$
