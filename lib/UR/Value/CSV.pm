package UR::Value::CSV;

use strict;
use warnings;

require UR;
our $VERSION = "0.29"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::CSV',
    is => ['UR::Value'],
    english_name => 'blob',
);

1;
#$Header$
