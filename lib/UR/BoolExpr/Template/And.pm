package UR::BoolExpr::Template::And;

use warnings;
use strict;
our $VERSION = "0.30"; # UR $VERSION;;

require UR;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    is              => ['UR::BoolExpr::Template::Composite'],
);

sub _underlying_keys {
    my $self = shift;
    my $logic_detail = $self->logic_detail;
    return unless $logic_detail;
    my @underlying_keys = split(",",$logic_detail);
    return @underlying_keys;
}

# sub get_underlying_rules_for_values {

sub get_underlying_rule_templates {
    my $self = shift;
    my @underlying_keys = grep { substr($_,0,1) eq '-' ? () : ($_) } $self->_underlying_keys();
    my $subject_class_name = $self->subject_class_name;
    return map {                
            UR::BoolExpr::Template::PropertyComparison
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
    return grep { $property_name eq $_->property_name } @underlying_templates;
}

sub evaluate_subject_and_values {
    my $self = shift;
    my $subject = shift;

    return unless (ref($subject) && $subject->isa($self->subject_class_name));

    if (my @underlying = $self->get_underlying_rule_templates) {
        while (my $underlying = shift (@underlying)) {
            my $value = shift @_;
            unless ($underlying->evaluate_subject_and_values($subject, $value)) {
                return;
            }
        }
    }
    return 1;
}


1;

=pod

=head1 NAME

UR::BoolExpr::And -  a rule which is true if ALL the underlying conditions are true 

=head1 SEE ALSO

UR::BoolExpr;(3)

=cut 
