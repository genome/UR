
package UR::BoolExpr::Template::PropertyComparison::Equals;

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
    my @property_value = $subject->$property_name;
    no warnings;
    if (@property_value == 1) {
        return ($property_value[0] eq $comparison_value ? 1 : '');
    }
    elsif (@property_value == 0) {
        return ($comparison_value eq '' ? 1 : '');
    }
    else {
        for (@property_value) {
            return 1 if $_ eq $comparison_value
        }
        return '';
    }
}


1;
