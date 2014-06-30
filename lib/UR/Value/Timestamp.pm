package UR::Value::Timestamp;
use strict;
use warnings;
require UR;
our $VERSION = "0.42_03"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::Timestamp',
    is => ['UR::Value::DateTime'],
);

1;
#$Header$
