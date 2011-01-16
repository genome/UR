
package UR::BoolExpr::Template::PropertyComparison::LessThan;

use strict;
use warnings;
require UR;
our $VERSION = "0.26"; # UR $VERSION;

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

    my $cv_is_number = Scalar::Util::looks_like_number($comparison_value);

    no warnings 'uninitialized';
    foreach my $property_value ( @property_value ) {
        my $pv_is_number = Scalar::Util::looks_like_number($property_value);

        if ($cv_is_number and $pv_is_number) {
            return 1 if ( $property_value < $comparison_value );
        } else {
             return 1 if ( $property_value lt $comparison_value );
        }
    }
    return '';
}


1;

=pod

=head1 NAME

UR::BoolExpr::Template::PropertyComparison::LessThan - perform a less than test

=head1 DESCRIPTION 

If the property returns multiple values, this comparison returns true if any of the values are
less than the comparison value

=cut

