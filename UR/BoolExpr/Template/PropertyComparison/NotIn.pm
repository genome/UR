
package UR::BoolExpr::Template::PropertyComparison::NotIn;

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
    my $comparison_value = shift;    
    my $property_name = $self->property_name;    
    my $property_value = $subject->$property_name;
    no warnings;
    for (@$comparison_value) {
        return 0 if ($property_value eq $_ ? 1 : '');
    }
    return 1;
}


1;
