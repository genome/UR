package UR::Value::ARRAY;

use strict;
use warnings;

require UR;
our $VERSION = "0.30"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::ARRAY',
    is => ['UR::Value::PerlReference'],
);

1;
#$Header$
