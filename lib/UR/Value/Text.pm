package UR::Value::Text;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Value::Text',
    is => ['UR::Value'],
    english_name => 'text',
);

1;
#$Header$
