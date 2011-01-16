package UR::Namespace::Command::Sys;
use warnings;
use strict;
use UR;
our $VERSION = "0.26"; # UR $VERSION;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command',
    doc => 'service launchers'
);

1;
