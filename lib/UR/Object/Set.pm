package UR::Object::Set;

use strict;
use warnings;
use UR;
our $VERSION = "0.30"; # UR $VERSION;

our @CARP_NOT = qw( UR::Object::Type );

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

# I'll neave this in here commented out for the future
# It's intended to keep 'count' for sets updated in real-time as objects are 
# created/deleted/updated
#sub _load {
#    my $class = shift;
#    my $self = $class->SUPER::_load(@_);
#
#    my $member_class_name = $rule->subject_class_name;
#
#    my $rule = $self->rule
#    my $rule_template = $rule->template;
#
#    my @rule_properties = $rule_template->_property_names;
#    my %rule_values = map { $_ => $rule->value_for($_) } @rule_properties;
#
#    my %underlying_comparator_for_property = map { $_->property_name => $_ } $rule_template->get_underlying_rule_templates;
#
#    my @aggregates = qw( count );
#
#    $member_class_name->create_subscription(
#        note => 'set monitor '.$self->id,
#        priority => 0,
#        callback => sub {
#            # make sure the aggregate values get invalidated when objects change
#            my @agg_set = @$self{aggregates};
#            return unless exists(@agg_set);   # returns only if none of the aggregates have values
#
#            my ($changed_object, $changed_property, $old_value, $new_value) = @_;
#
#            if ($changed_property eq 'create') {
#                if ($rule->evaluate($changed_object)) {
#                    $self->{'count'}++;
#                }
#            } elsif ($changed_property eq 'delete') {
#                if ($rule->evaluate($changed_object)) {
#                    $self->{'count'}--;
#                }
#            } elsif (exists $value_index_for_property{$changed_property}) {
#
#                my $comparator = $underlying_comparator_for_property{$changed_property};
#
#                # HACK!
#                $changed_object->{$changed_property} = $old_value;
#                my $evaled_before = $comparator->evaluate_subject_and_values($changed_object,$rule_values{$changed_property});
#
#                $changed_object->{$changed_property} = $new_value;
#                my $evaled_after = $comparator->evaluate_subject_and_values($changed_object,$rule_values{$changed_property});
#
#                if ($evaled_before and ! $evaled_after) {
#                    $self->{'count'}--;
#                } elsif ($evaled_after and ! $evaled_before) {
#                    $self->{'count'}++;
#                }
#            }
#        }
#    );
#
#    return $self;
#}
    

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
    my @groups = UR::Context->current->get_objects_for_class_and_rule( 
        $self->member_class_name, 
        $grouping_rule, 
        undef,  #$load, 
        0,      #$return_closure, 
    );
    return $self->context_return(@groups);
}

sub count {
    my $self = shift;

    Carp::croak("count() is a group operation, and is not writable") if @_;

    # If there are no member-class objects with changes, we can just interrogate the DB
    my $has_changes = 0;
    foreach my $obj ( $self->member_class_name->is_loaded() ) {
        if ($obj->__changes__) {
            $has_changes = 1;
            last;
        }
    }

    if ($has_changes) {
        my @members = $self->members;
        $self->{'count'} = scalar(@members);

    } elsif (! exists $self->{'count'}) {
        my $count_rule = $self->rule->add_filter(-group_by => []);
        UR::Context->current->get_objects_for_class_and_rule(
              $self->member_class_name,
              $count_rule,
              1,    # load
              0,    # return_closure
         );
    }
    return $self->{'count'};
}

sub AUTOSUB {
    my ($method,$class) = @_;
    if (ref $class) {
        $class = $class->class;
    }
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
            Carp::croak("Multiple matches for $class method '$method' called in scalar context.  The set has ".scalar(@values)." values to return") if @values > 1 and not wantarray;
            return $values[0];
        }
    }; 
}

1;

