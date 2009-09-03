
package UR::BoolExpr::Template::PropertyComparison::GreaterOrEqual;

use strict;
use warnings;

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
    return ($property_value >= $comparison_value || $property_value ge $comparison_value ? 1 : '');
}


1;

=pod

=head1 NAME

UR::BoolExpr::Template::PropertyComparison::GreaterOrEqual - Perform a greater than or equal test

=cut
