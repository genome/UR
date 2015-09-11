package UR::Value::Number;
use strict;
use warnings;
require UR;
our $VERSION = "0.44"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::Number',
    is => ['UR::Value'],
);

1;
