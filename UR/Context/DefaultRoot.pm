package UR::Context::DefaultRoot;
use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Context::DefaultRoot',
    is => ['UR::Context::Root'],
    english_name => 'ur context default base',
    doc => 'The base context used when no special base context is specified.',
);

1;

