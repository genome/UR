package UR::Value::DateTime;

use strict;
use warnings;

require UR;
our $VERSION = "0.34"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::DateTime',
    is => ['UR::Value'],
    english_name => 'datetime',
);

1;
#$Header$
