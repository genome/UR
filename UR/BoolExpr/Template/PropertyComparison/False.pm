
package UR::BoolExpr::Template::PropertyComparison::False;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name  => __PACKAGE__, 
    is => ['UR::BoolExpr::Template::PropertyComparison'],
);

sub evaluate_subject_and_values {
    my $self = shift;
    my $subject = shift;
    my $comparison_value = shift;    # not used...

    my $property_name = $self->property_name;    
    my @property_value = $subject->$property_name;
    if (@property_value == 0 ) {
        # No return values... return true
        return 1; 
    } elsif (@property_value == 1) {
        # 1 return value... return the negation of it
        return ! $property_value[0];
    } else {
        # More than 1 return value... return false
        return 0;
    }
}


1;
