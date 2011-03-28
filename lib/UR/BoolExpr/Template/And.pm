package UR::BoolExpr::Template::And;

use warnings;
use strict;
our $VERSION = "0.30"; # UR $VERSION;;

require UR;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    is              => ['UR::BoolExpr::Template::Composite'],
);

sub _variable_value_count {
    my $self = shift;
    my $k = $self->_underlying_keys;
    my $v = $self->_constant_values || 0;
    return $k-$v;
}

sub _underlying_keys {
    my $self = shift;
    my $logic_detail = $self->logic_detail;
    return unless $logic_detail;
    my @underlying_keys = split(",",$logic_detail);
    return @underlying_keys;
}

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

sub params_list_for_values {
    # This is the reverse of the bulk of resolve.
    # It returns the params in list form, directly coercable into a hash if necessary.
    # $r = UR::BoolExpr->resolve($c1,@p1);
    # ($c2, @p2) = ($r->subject_class_name, $r->params_list);
    
    my $rule_template = shift;
    my @values_sorted = @_;
    
    my @keys_sorted = $rule_template->_underlying_keys;
    my @constant_values_sorted = $rule_template->_constant_values;
    
    my @params;
    my ($v,$c) = (0,0);
    for (my $k=0; $k<@keys_sorted; $k++) {
        my $key = $keys_sorted[$k];                        
        #if (substr($key,0,1) eq "_") {
        #    next;
        #}
        #elsif (substr($key,0,1) eq '-') {
        if (substr($key,0,1) eq '-') {
            my $value = $constant_values_sorted[$c];
            push @params, $key, $value;        
            $c++;
        }
        else {
            my ($property, $op) = ($key =~ /^(\-*\w+)\s*(.*)$/);        
            unless ($property) {
                die "bad key $key in @keys_sorted";
            }
            my $value = $values_sorted[$v];
            if ($op) {
                if ($op ne "in") {
                    if ($op =~ /^(.+)-(.+)$/) {
                        $value = { operator => $1, value => $value, escape => $2 };
                    }
                    else {
                        $value = { operator => $op, value => $value };
                    }
                }
            }
            push @params, $property, $value;
            $v++;
        }
    }

    return @params; 
}


1;

=pod

=head1 NAME

UR::BoolExpr::And -  a rule which is true if ALL the underlying conditions are true 

=head1 SEE ALSO

UR::BoolExpr;(3)

=cut 
