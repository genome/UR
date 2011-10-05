
package UR::BoolExpr::Template::PropertyComparison::NotIn;

use strict;
use warnings;
use UR;
our $VERSION = "0.34"; # UR $VERSION;

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

    # undef should match missing values, which will be sorted at the end - the sorter in
    # UR::BoolExpr::resolve() takes care of the sorting for us
    if (! @property_values and !defined($comparison_values->[-1])) {
        return '';
    }

    # If _all_ the comparison_values and property_values are numbers, then we can
    # use a numeric sorter.  If any one of them are strings, then use string sorting.

    my $compare_strings;
    if (Scalar::Util::blessed($comparison_values) and ref($comparison_values) eq 'ARRAYofAllNumbers') {
        $compare_strings = 0;
    } else {
        $compare_strings = 1;
    }
    if (! $compare_strings) {
        foreach my $v ( @property_values ) {
            if (! Scalar::Util::looks_like_number($v) ) {
                $compare_strings = 1;
                last;
            }
        }
    }

    my($sorter, $pv_idx, $cv_idx);
    if ($compare_strings) {
        $sorter = sub { return $property_values[$pv_idx] cmp $comparison_values->[$cv_idx] };
    } else {
        $sorter = sub { return $property_values[$pv_idx] <=> $comparison_values->[$cv_idx] };
    }

    # Binary search within @$comparison_values
    my $cv_min = 0;
    my $cv_max = $#$comparison_values;
    for ( $pv_idx = 0; $pv_idx < @property_values; $pv_idx++ ) {
        do {
            $cv_idx = ($cv_min + $cv_max) >> 1;
            my $result = &$sorter;
            if (!$result) {
                return '';
            } elsif ($result > 0) {
                $cv_min = $cv_idx + 1;
            } else {
                $cv_max = $cv_idx - 1;
            }
        } until ($cv_min > $cv_max);
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
