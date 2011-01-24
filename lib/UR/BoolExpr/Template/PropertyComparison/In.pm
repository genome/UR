
package UR::BoolExpr::Template::PropertyComparison::In;

use strict;
use warnings;
use UR;
our $VERSION = "0.29"; # UR $VERSION;

UR::Object::Type->define(
    class_name  => __PACKAGE__, 
    is => ['UR::BoolExpr::Template::PropertyComparison'],
    doc => "Returns true if any of the property's values appears in the comparison value list",
);

sub evaluate_subject_and_values {
    my $self = shift;
    my $subject = shift;
    my $comparison_values = shift;
    my $property_name = $self->property_name;
    my @property_values = $subject->$property_name;

    if (@property_values == 1 and ref($property_values[0]) eq 'ARRAY') {
        @property_values = @{$property_values[0]};
    }

    no warnings qw(uninitialized);
    foreach my $comparison_value (@$comparison_values) {
        my $cv_is_number = Scalar::Util::looks_like_number($comparison_value);

        # undef should match missing values
        if (! defined($comparison_value) and ! scalar(@property_values)) {
            return 1;
        }

        foreach my $property_value ( @property_values ) {
            my $pv_is_number = Scalar::Util::looks_like_number($property_value);

            if ($cv_is_number and $pv_is_number) {
                return 1 if ($property_value == $comparison_value);
            } else {
                return 1 if ($property_value eq $comparison_value);
            }
        }
    }
    return '';
}


1;

=pod

=head1 NAME

UR::BoolExpr::Template::PropertyComparison::In - perform an In test

=head1 DESCRIPTION

Returns true if any of the property's values appears in the comparison value list.
Think of 'in' as short for 'intersect', and not just SQL's 'IN' operator.

=cut
