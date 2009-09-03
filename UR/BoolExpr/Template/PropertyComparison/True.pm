
package UR::BoolExpr::Template::PropertyComparison::True;

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
    return @property_value;  # The template's evaluate_subject_and_values() will evaluate this in boolean context
}


1;

=pod

=head1 NAME

UR::BoolExpr::Template::PropertyComparison::True - Evaluate to true of the property's value is true

=cut
