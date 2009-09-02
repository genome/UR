
package UR::Object::Type::AccessorWriter::Sum;

use strict;
use warnings;

sub calculate {
    my $self = shift;
    my $object = shift;
    my $properties = shift;
    my $sum = 0;
    for my $property (@$properties) {
        $sum += $object->$property
    }   
    return $sum;
};

1;
