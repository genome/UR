
package UR::BoolExpr::Template::PropertyComparison::True;

use strict;
use warnings;
use UR;
our $VERSION = $UR::VERSION;

UR::Object::Type->define(
    class_name  => __PACKAGE__, 
    is => ['UR::BoolExpr::Template::PropertyComparison'],
);

sub evaluate_subject_and_values {
    my $self = shift;
    my $subject = shift;

    my $property_name = $self->property_name;
    my @property_value = eval { $subject->$property_name; };
    if ($@) {
        $DB::single = 1;
    }
    no warnings;
    if (@property_value == 0) {
        return '';

    } else {
        for (@property_value) {
            return 1 if ($_);     # Returns true if _any_ of the values are true
        }
        return '';
    }
}


1;

=pod

=head1 NAME

UR::BoolExpr::Template::PropertyComparison::True - Evaluates to true if the property's value is true

If the property returns multiple values, this comparison returns true if any of the values are true

=cut
