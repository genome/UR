package UR::Value::SCALAR;

use strict;
use warnings;

require UR;
our $VERSION = "0.41_04"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::SCALAR',
    is => ['UR::Value::PerlReference'],
);

1;
#$Header$
