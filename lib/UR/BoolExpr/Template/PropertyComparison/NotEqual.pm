
package UR::BoolExpr::Template::PropertyComparison::NotEqual;

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

    no warnings 'uninitialized';
    if (@property_value == 0) {
        return ($comparison_value eq '' ? '' : 1);
    }

    my $cv_is_number = Scalar::Util::looks_like_number($comparison_value);

    foreach my $property_value ( @property_value ) {
        my $pv_is_number = Scalar::Util::looks_like_number($property_value);

        if ($cv_is_number and $pv_is_number) {
             return '' if ( $property_value == $comparison_value );
        } else {
             return '' if ( $property_value eq $comparison_value );
        }
    }
    return 1;
}


1;

=pod

=head1 NAME

UR::BoolExpr::Template::PropertyComparison::NotEqual - Perform a not-equal test

=head1 DESCRIPTION

If the property returns multiple values, this comparison returns false if any if the values
are equal to the comparison value

=cut
