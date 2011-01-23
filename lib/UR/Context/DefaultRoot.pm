package UR::Context::DefaultRoot;
use strict;
use warnings;

require UR;
our $VERSION = "0.28"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Context::DefaultRoot',
    is => ['UR::Context::Root'],
    english_name => 'ur context default base',
    doc => 'The base context used when no special base context is specified.',
);

1;

=pod

=head1 NAME

UR::Context::DefaultRoot - The base context used when no special base context is specified

=cut
