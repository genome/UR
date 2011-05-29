package UR::Object::Set;

use strict;
use warnings;
use UR;
our $VERSION = "0.31"; # UR $VERSION;

our @CARP_NOT = qw( UR::Object::Type );

use overload ('""' => '__display_name__');
use overload ('==' => sub { $_[0] . ''  eq $_[1] . '' } );
use overload ('eq' => sub { $_[0] . ''  eq $_[1] . '' } );

class UR::Object::Set {
    is => 'UR::Value',
    is_abstract => 1,
    has => [
        rule                => { is => 'UR::BoolExpr', id_by => 'id' },
        rule_display        => { is => 'Text', via => 'rule', to => '__display_name__'},
        member_class_name   => { is => 'Text', via => 'rule', to => 'subject_class_name' },
        members             => { is => 'UR::Object', is_many => 1 }
    ],
    doc => 'an unordered group of distinct UR::Objects'
};

# override the UR/system display name
# this is used in stringification overload
sub __display_name__ {
    my $self = shift;
    my %b = $self->rule->_params_list;
    my $s = Data::Dumper->new([\%b])->Terse(1)->Indent(0)->Useqq(1)->Dump;
    $s =~ s/\n/ /gs;
    $s =~ s/^\s*{//; 
    $s =~ s/\}\s*$//;
    $s =~ s/\"(\w+)\" \=\> / $1 => /g;
    return '(' . ref($self) . ' ' . $s . ')';
}

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
    warn "the ability to get sets with member params is deprecated: $class $bx @params";
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

sub __aggregate__ {
    my $self = shift;
    my $f = shift;

    Carp::croak("$f is a group operation, and is not writable") if @_;

    # If there are no member-class objects with changes, we can just interrogate the DB
    my $has_changes = 0;
    foreach my $obj ( $self->member_class_name->is_loaded() ) {
        if ($obj->__changes__) {
            $has_changes = 1;
            last;
        }
    }

    if ($has_changes) {
        my $fname;
        my @fargs;
        if ($f =~ /^(\w+)\((.*)\)$/) {
            $fname = $1;
            @fargs = ($2 ? split(',',$2) : ());
        }
        else {
            $fname = $f;
            @fargs = ();
        }
        my $local_method = '__aggregate_' . $fname . '__';
        $self->{$f} = $self->$local_method(@fargs);
    } 
    elsif (! exists $self->{$f}) {
        my $rule = $self->rule->add_filter(-aggregate => [$f])->add_filter(-group_by => []);
        UR::Context->current->get_objects_for_class_and_rule(
              $self->member_class_name,
              $rule,
              1,    # load
              0,    # return_closure
         );
    }
    return $self->{$f};
}

sub __aggregate_count__ {
    my $self = shift;
    my @members = $self->members;
    return scalar(@members);
}

sub __aggregate_min__ {
    my $self = shift;
    my $p = shift;
    my $min = undef;
    no warnings;
    for my $member ($self->members) {
        my $v = $member->$p;
        next unless defined $v;
        $min = $v if not defined $min or $v < $min;
    }
    return $min;
}

sub __aggregate_max__ {
    my $self = shift;
    my $p = shift;
    my $max = undef;
    no warnings;
    for my $member ($self->members) {
        my $v = $member->$p;
        next unless defined $v;
        $max = $v if not defined $max or $v > $max;
    }
    return $max;
}

sub __aggregate_sum__ {
    my $self = shift;
    my $p = shift;
    my $sum = undef;
    no warnings;
    for my $member ($self->members) {
        my $v = $member->$p;
        next unless defined $v;
        $sum += $v;
    }
    return $sum;
}

sub __related_set__ {
    my $self = $_[0];
    my $property_name = $_[1];
    my $bx1 = $self->rule;
    my $bx2 = $bx1->reframe($property_name);
    return $bx2->subject_class_name->define_set($bx2);
}

require Class::AutoloadCAN;
Class::AutoloadCAN->import();

sub CAN {
    my ($class,$method,$self) = @_;
    
    if ($method =~ /^__aggregate_(.*)__/) {
        # prevent circularity issues since this actually calls ->can();
        return;
    }

    my $member_class_name = $class;
    $member_class_name =~ s/::Set$//g; 
    return unless $member_class_name; 
    if ($member_class_name->can($method)) {
        my $member_class_meta = $member_class_name->__meta__;
        my $member_property_meta = $member_class_meta->property_meta_for_name($method);
        
        # regular property access
        if ($member_property_meta) {
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
                    Carp::confess("Multiple matches for $class method '$method' called in scalar context.  The set has ".scalar(@values)." values to return") if @values > 1 and not wantarray;
                    return $values[0];
                }
            }; 
        }

        # set relaying with $s->foo_set->bar_set->baz_set;
        if (my ($property_name) = ($method =~ /^(.*)_set$/)) {
            return sub {
                shift->__related_set__($property_name, @_)
            }
        }

        # other method
        return sub {
            my $self = shift;
            if (@_) {
                Carp::croak("Cannot use method $method as a mutator: Set properties are not mutable");
            }
            my @members = $self->members;
            my @values = map { $_->$method } @members;
            return @values if wantarray;
            return if not defined wantarray;
            Carp::confess("Multiple matches for $class method '$method' called in scalar context.  The set has ".scalar(@values)." values to return") if @values > 1 and not wantarray;
            return $values[0];
        }; 

    }
    else {
        # a possible aggregation function
        # see if the method ___aggregate__ uses exists, and if so, delegate to __aggregate__
        # TODO: delegate these to aggregation function modules instead of having them in this module
        my $aggregator = '__aggregate_' . $method . '__';
        if ($self->can($aggregator)) {
            return sub {
                my $self = shift;
                my $f = $method;
                if (@_) {
                    $f .= '(' . join(',',@_) . ')';
                }
                return $self->__aggregate__($f);
            };
        }
        
        # set relaying with $s->foo_set->bar_set->baz_set;
        if (my ($property_name) = ($method =~ /^(.*)_set$/)) {
            return sub {
                shift->__related_set__($property_name, @_)
            }
        }
    }
    print ">>> ck $method\n";
    return;
}

1;

