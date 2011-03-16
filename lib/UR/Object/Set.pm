package UR::Object::Set;

use strict;
use warnings;
use UR;
our $VERSION = "0.30"; # UR $VERSION;

class UR::Object::Set {
    is => 'UR::Value',
    is_abstract => 1,
    has => [
        rule                => { is => 'UR::BoolExpr', id_by => 'id' },
        rule_display        => { via => 'rule', to => '__display_name__'},
        member_class_name   => { via => 'rule', to => 'subject_class_name' },
        members             => { is => 'UR::Object', is_many => 1 }
    ],
    doc => 'an unordered group of distinct UR::Objects'
};

sub get_with_special_parameters {
    my $class = shift;
    my $bx = shift;
    my @params = @_;

    my $member_class = $class;
    $member_class =~ s/::Set$//;

    my $rule = UR::BoolExpr->resolve($member_class, $bx->params_list, @params);

    return $class->get($rule->id);
}

sub members {
    my $self = shift;
    my $rule = $self->rule;
    while (@_) {
        $rule = $rule->add_filter(shift, shift);
    }
    return $self->member_class_name->get($rule);
}

sub subset {
    my $self = shift;
    my $member_class_name = $self->member_class_name;
    my $bx = UR::BoolExpr->resolve($member_class_name,@_);
    my $subset = $self->class->get($bx->id);
    return $subset;
}

sub group_by {
    my $self = shift;
    my @group_by = @_;
    my $grouping_rule = $self->rule->add_filter(-group_by => \@group_by);
    my @groups = UR::Context->get_objects_for_class_and_rule( 
        $self->member_class_name, 
        $grouping_rule, 
        undef,  #$load, 
        0,      #$return_closure, 
    );
    return @groups;
}

sub count {
    $_[0]->__init unless $_[0]->{__init};
    return $_[0]->{count};
}

sub AUTOSUB {
    my ($method,$class) = @_;
    my $member_class_name = $class;
    $member_class_name =~ s/::Set$//g; 
    return unless $member_class_name; 
    my $member_class_meta = $member_class_name->__meta__;
    my $member_property_meta = $member_class_meta->property_meta_for_name($method);
    return unless $member_property_meta;
    return sub {
        my $self = shift;
        if (@_) {
            Carp::croak("Cannot use method $method as a mutator: Set properties are not mutable");
        }
        my $rule = $self->rule;
        if ($rule->specifies_value_for($method)) {
            return $rule->value_for($method);
        } 
        else {
            my @members = $self->members;
            my @values = map { $_->$method } @members;
            return @values if wantarray;
            return if not defined wantarray;
            Carp::croak("Multiple matches for Set method '$method' called in scalar context.  The set has ".scalar(@values)." values to return") if @values > 1 and not wantarray;
            return $values[0];
        }
    }; 
}

1;

