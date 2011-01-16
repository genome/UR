package UR::BoolExpr::Template::Or;

use warnings;
use strict;
our $VERSION = "0.27"; # UR $VERSION;;

require UR;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    is              => ['UR::BoolExpr::Template::Composite'],    
);

sub _underlying_keys {
    my $self = shift;
    my $logic_detail = $self->logic_detail;
    return unless $logic_detail;
    my @underlying_keys = split("|",$logic_detail);
    return @underlying_keys;
}

# sub get_underlying_rules_for_values

sub get_underlying_rule_templates {
    my $self = shift;
    my @underlying_keys = $self->_underlying_keys();
    my $subject_class_name = $self->subject_class_name;
    return map {                
            UR::BoolExpr::Template::And
                ->_get_for_subject_class_name_and_logic_detail(
                    $subject_class_name,
                    $_
                );
        } @underlying_keys;
}

sub specifies_value_for {
    my ($self, $property_name) = @_;
    Carp::confess() if not defined $property_name;
    my @underlying_templates = $self->get_underlying_rule_templates();        
    my @all_specified;
    for my $template (@underlying_templates) {
        my @specified = $template->specifies_value_for($property_name);
        if (@specified) {
            push @all_specified, @specified;
        }
        else {
            return;
        }
    }
    return @all_specified;
}

sub evaluate_subject_and_values {
    my $self = shift;
    my $subject = shift;

    return unless (ref($subject) && $subject->isa($self->subject_class_name));

    my @underlying = $self->get_underlying_rule_templates;
    while (my $underlying = shift (@underlying)) {
        my $n = $underlying->num_values;
        my @next_values = splice(@_,0,$n);
        if ($underlying->evaluate_subject_and_values($subject,@_)) {
            return 1;
        }
    }
    return;
}

1;

=pod

=head1 NAME

UR::BoolExpr::Or -  a rule which is true if ANY of the underlying conditions are true 

=head1 SEE ALSO

UR::BoolExpr;(3)

=cut 
