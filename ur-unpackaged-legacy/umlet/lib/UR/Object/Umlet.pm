use strict;
use warnings;

package UR::Object::Umlet;

# Top-level class for Umlet diagram related things
use UR;
our $VERSION = "0.26"; # UR $VERSION;

UR::Object::Type->define(
    is => 'UR::Object',
    class_name      => __PACKAGE__,
    is_abstract => 1,
);


# Turns things like '<' into '&lt;'
sub escape_xml_data {
my($self,$string) = @_;

    $string =~ s/\</&lt;/g;
    $string =~ s/\>/&gt;/g;

    return $string;
}

1;

=pod

=head1 NAME

UR::Object::Umlet - Base class for entities diagrammed by Umlet

=head1 DESCRIPTION

This class is used by the class and schema diagrammers
(L<UR::Namespace::Command::Update::ClassDiagram> and 
L<UR::Namespace::Command::Update::SchemaDiagram>) and represents
elements of a diagram.

=cut
