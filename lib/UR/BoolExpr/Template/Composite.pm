package UR::BoolExpr::Template::Composite;

use warnings;
use strict;
our $VERSION = "0.28"; # UR $VERSION;;

require UR;

UR::Object::Type->define(
    class_name  => __PACKAGE__,
    is          => ['UR::BoolExpr::Template'],
);

# sub _underlying_keys {

sub get_underlying_rules_for_values {
    my $self = shift;
    my @values = @_;    
    my @underlying_templates = $self->get_underlying_rule_templates();
    my @underlying_rules;
    for my $template (@underlying_templates) {
        my $n = $template->num_values;
        my $value_id = $template->values_to_value_id(splice(@values,0,$n));
        my $rule_id = UR::BoolExpr->__meta__->resolve_composite_id_from_ordered_values($template->id,$value_id);
        my $rule = UR::BoolExpr->get($rule_id);
        push @underlying_rules, $rule;
    }
    return @underlying_rules;
}

# sub get_underlying_rule_templates {

# sub specifies_value_for {

# evalutate_subject_and_values {

1;

=pod

=head1 NAME

UR::BoolExpr::Composite - an "and" or "or" rule

=head1 SYNOPSIS

@r = $r->get_underlying_rules();
for (@r) {
    print $r->evaluate($c1);
}

=head1 DESCRIPTION

=head1 SEE ALSO

UR::Object(3), UR::BoolExpr, UR::BoolExpr::Template, UR::BoolExpr::Template::And, UR::BoolExpr::Template::Or, UR::BoolExpr::Template::PropertyComparison

=cut
