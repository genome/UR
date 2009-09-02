package UR::Value::DateTime;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Value::DateTime',
    is => ['UR::Value'],
    english_name => 'ur value datetime',
);

1;
#$Header$
