package UR::Object::Property::ID;

use strict;
use warnings;
our $VERSION = $UR::VERSION;;

sub get_property {
    my $self = shift;
    return UR::Object::Property->get(
        class_name => $self->class_name,
        property_name => $self->property_name
    );
}

1;

