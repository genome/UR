package UR::Value::URL;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Value::URL',
    is => ['UR::Value::Text'],
);

1;
#$Header$
