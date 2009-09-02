package UR::Context::DefaultBase;
use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Context::DefaultBase',
    is => ['UR::Context::Base'],
    english_name => 'ur context default base',
    doc => 'The base context used when no special base context is specified.',
);

1;

