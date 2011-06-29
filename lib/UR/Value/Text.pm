package UR::Value::Text;

use strict;
use warnings;

require UR;
our $VERSION = "0.32"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::Text',
    is => ['UR::Value'],
    english_name => 'text',
);

1;
#$Header$
