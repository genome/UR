package UR::Value::SCALAR;

use strict;
use warnings;

require UR;
our $VERSION = "0.30"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::SCALAR',
    is => ['UR::Value'],
);

1;
#$Header$
