package UR::Value::HASH;

use strict;
use warnings;

require UR;
our $VERSION = $UR::VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::HASH',
    is => ['UR::Value::PerlReference'],
);

1;
#$Header$
