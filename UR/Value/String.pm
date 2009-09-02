package UR::Value::String;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Value::String',
    is => ['UR::Value'],
    english_name => 'ur value string',
);

1;
#$Header$
