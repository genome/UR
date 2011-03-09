
package UR::BoolExpr::Template::PropertyComparison::Like;

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

    return '' unless defined ($comparison_value);  # property like NULL should always be false

    my $escape = shift;    

    my $regex = $self->
        comparison_value_and_escape_character_to_regex(
            $comparison_value,
            $escape
        );
    my $property_name = $self->property_name;    

    no warnings 'uninitialized';
    my @property_value = $subject->$property_name;
    foreach my $value ( @property_value ) {
        return 1 if $value =~ $regex;
    }
    return '';
}

1;

=pod 

=head1 NAME 

UR::BoolExpr::Template::PropertyComparison::Like - perform an SQL-ish like test

=head1 DESCRIPTION

The input test value is assummed to be an SQL 'like' value, where '_'
represents a one character wildcard, and '%' means a 0 or more character
wildcard.  It gets converted to a perl regular expression and used to match
against an object's properties.

If the property returns multiple values, this comparison returns true if any of the values
match.


=cut

