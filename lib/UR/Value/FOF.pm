package UR::Value::FOF;

use strict;
use warnings;

require UR;
our $VERSION = "0.29"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::FOF',
    is => ['UR::Value'],
    english_name => 'blob',
);

1;
#$Header$
