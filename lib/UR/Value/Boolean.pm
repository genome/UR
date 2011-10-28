package UR::Value::Boolean;
use strict;
use warnings;

require UR;
our $VERSION = "0.35"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::Boolean',
    is => ['UR::Value'],
);

1;
