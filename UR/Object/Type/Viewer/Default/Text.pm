package UR::Object::Type::Viewer::Default::Text;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::Viewer::Default::Text',
    has => [
       default_aspects => { is => 'ARRAY', is_constant => 1, value => ['is','direct_property_names'], },
    ],
);


1;

=pod

=head1 NAME

UR::Object::Type::Viewer::Default::Text - Viewer class for class metaobjects

=head1 DESCRIPTION

This class is used by L<UR::Namespace::Command::Info> and L<UR::Namespace::Command::Description>
to construct the text outputted.

=cut
