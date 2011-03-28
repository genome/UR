package UR::Value::Decimal;


use strict;
use warnings;

require UR;
our $VERSION = "0.30"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::Decimal',
    is => ['UR::Value::Number'],
    english_name => 'decimal',
);

1;
#$Header$
