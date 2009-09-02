
package UR::BoolExpr::Template::PropertyComparison::Between;

use strict;
use warnings;

UR::Object::Type->define(
    class_name  => __PACKAGE__, 
    is => ['UR::BoolExpr::Template::PropertyComparison'],
);

sub evaluate_subject_and_values {
    my $self = shift;
    my $subject = shift;
    my $lower_bound = shift;
    my $upper_bound = shift;
    my $property_name = $self->property_name;    
    my $property_value = $subject->$property_name;
    no warnings;
    return (
        (
            $property_value >= $lower_bound 
            and
            $property_value <= $upper_bound
        )
        ||
        (
            $property_value ge $lower_bound 
            and
            $property_value le $upper_bound
        )        
        ? 1 
        : ''
    );
}


1;
