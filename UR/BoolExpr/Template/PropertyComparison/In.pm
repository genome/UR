
package UR::BoolExpr::Template::PropertyComparison::In;

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
    my @property_values = $subject->$property_name;

    if (@property_values == 1 and ref($property_values[0]) eq 'ARRAY') {
        @property_values = @{$property_values[0]};
    }

    #my $property_value = $subject->$property_name;
    no warnings;
    #for (@$comparison_value) {
    #    return 1 if ($property_value eq $_ ? 1 : '');
    #}
    foreach my $comparison_value (@$comparison_value) {
        foreach my $property_value ( @property_values ) {
            return 1 if ($property_value eq $comparison_value);
        }
    }
    return;
}


1;
