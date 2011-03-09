
package UR::BoolExpr::Template::PropertyComparison::Matches;

use strict;
use warnings;
use UR;
our $VERSION = "0.30"; # UR $VERSION;

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
    foreach my $property_value ( @property_value ) {
        return 1 if ( $property_value =~ m/$comparison_value/ );
    }
    return '';
}


1;

=pod

=head1 NAME 

UR::BoolExpr::Template::PropertyComparison::Matches - perform a Perl regular expression match

=head1 DESCRIPTION

If the property returns multiple values, this comparison returns true if any of the values match

=cut
