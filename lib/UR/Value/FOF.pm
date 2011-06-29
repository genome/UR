package UR::Value::FOF;

use strict;
use warnings;

require UR;
our $VERSION = "0.32"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::FOF',
    is => ['UR::Value'],
    english_name => 'fof',
);

1;
#$Header$
