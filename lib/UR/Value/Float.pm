package UR::Value::Float;
use strict;
use warnings;
require UR;
our $VERSION = "0.392"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::Float',
    is => ['UR::Value::Number'],
);

1;
