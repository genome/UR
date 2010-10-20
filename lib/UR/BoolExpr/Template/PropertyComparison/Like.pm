
package UR::BoolExpr::Template::PropertyComparison::Like;

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

    return '' unless defined ($comparison_value);  # property like NULL should always be false

    my $escape = shift;    

    my $regex = $self->
        comparison_value_and_escape_character_to_regex(
            $comparison_value,
            $escape
        );
    my $property_name = $self->property_name;    
    my $property_value = $subject->$property_name;
    no warnings;
    return ($property_value =~ $regex ? 1 : '');
}

sub comparison_value_and_escape_character_to_regex {    
    my ($class, $value, $escape) = @_;
	
    return '' unless defined($value);

    # anyone who uses the % as an escape character deserves to suffer
    if ($value eq '%') {
	return '^.+$';
    }
    
    my $regex = $value;
    # Handle the escape sequence    
    if (defined $escape)
    {
        $escape =~ s/\\/\\\\/g; # replace \ with \\
        $regex =~ s/(?<!${escape})\%/\.\*/g;
        $regex =~ s/(?<!${escape})\_/./g;
        #LSF: Take away the escape characters.
        $regex =~ s/$escape\%/\%/g;
        $regex =~ s/$escape\_/\_/g;
    }
    else
    {
        $regex =~ s/\%/\.\*/g;
        $regex =~ s/\_/./g;
    }
               
    #TODO: escape all special characters in the regex.
    
    # Wrap the regex in delimiters.
    $regex = "^${regex}\$";
    return $regex;
}

1;

=pod 

=head1 NAME 

UR::BoolExpr::Template::PropertyComparison::Like - Perform an SQL-ish like test

=head1 DESCRIPTION

The input test value is assummed to be an SQL 'like' value, where '_'
represents a one character wildcard, and '%' means a 0 or more character
wildcard.  It gets converted to a perl regular expression and used to match
against an object's properties

=cut

