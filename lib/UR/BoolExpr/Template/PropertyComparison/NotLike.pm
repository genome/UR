
package UR::BoolExpr::Template::PropertyComparison::NotLike;

use strict;
use warnings;
use UR;
our $VERSION = "0.29"; # UR $VERSION;

UR::Object::Type->define(
    class_name  => __PACKAGE__, 
    is => ['UR::BoolExpr::Template::PropertyComparison'],
);

sub evaluate_subject_and_values {
    my $self = shift;
    my $subject = shift;
    my $comparison_value = shift;    
    my $escape = shift;    
    my $regex = $self->
        comparison_value_and_escape_character_to_regex(
            $comparison_value,
            $escape
        );
    my $property_name = $self->property_name;    
    my @property_value = $subject->$property_name;

    no warnings 'uninitialized';
    foreach my $property_value ( @property_value ) {
        return '' if ($property_value =~ $regex);
    }
    return 1;
}

1;

=pod

=head1 NAME

UR::BoolExpr::Template::PropertyComparison::NotLike - perform a negated SQL-ish like test

=head1 DESCRIPTION

The input test value is assummed to be an SQL 'like' value, where '_'
represents a one character wildcard, and '%' means a 0 or more character
wildcard.  It gets converted to a perl regular expression and used in a
negated match against an object's properties

If the property returns multiple values, this comparison returns false if
any of the values matches the pattern

=cut

