package UR::Value::PerlReference;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Value::PerlReference',
    is => ['UR::Value'],
);

1;
#$Header$
