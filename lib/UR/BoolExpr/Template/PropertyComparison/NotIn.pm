
package UR::BoolExpr::Template::PropertyComparison::NotIn;

use strict;
use warnings;
use UR;
our $VERSION = "0.33"; # UR $VERSION;

UR::Object::Type->define(
    class_name  => __PACKAGE__, 
    is => ['UR::BoolExpr::Template::PropertyComparison'],
    doc => "Returns false if any of the property's values appears in the comparison value list",
);

sub _compare {
    my ($class,$comparison_values,@property_values) = @_;

    if (@property_values == 1 and ref($property_values[0]) eq 'ARRAY') {
        @property_values = @{$property_values[0]};
    }

    no warnings qw(uninitialized);
    foreach my $comparison_value (@$comparison_values) {
        my $cv_is_number = Scalar::Util::looks_like_number($comparison_value);

        # undef should match missing values
        if (! defined($comparison_value) and ! scalar(@property_values)) {
            return '';
        }

        foreach my $property_value ( @property_values ) {
            my $pv_is_number = Scalar::Util::looks_like_number($property_value);

            if ($cv_is_number and $pv_is_number) {
                return '' if ($property_value == $comparison_value);
            } else {
                return '' if ($property_value eq $comparison_value);
            }
        }
    }
    return 1;
}


1;

=pod

=head1 NAME

UR::BoolExpr::Template::PropertyComparison::NotIn - perform a negated In comparison

=head1 DESCRIPTION

Returns false if any of the property's values appears in the comparison value list

=cut
