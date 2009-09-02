use strict;
use warnings;

package UR::Object::Umlet;

# Top-level class for Umlet diagram related things
use UR;

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
