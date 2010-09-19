package UR::Object::Type::View::Default::Umlet;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::View'
);

# This will go away when UR::Object::Type stuff is all moved to UR::Object stuff

1;

=pod

=head1 NAME

UR::Object::Type::View::Default::Umlet - View class for class metaobjects

=head1 DESCRIPTION

This class is used by L<UR::Namespace::Command::Update::ClassDiagram> and
C<ur update class-diagram> to create Umlet diagrams showing the class
structure.

=cut
