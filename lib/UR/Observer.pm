
package UR::Observer;

use strict;
use warnings;

require UR;
our $VERSION = "0.35"; # UR $VERSION;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    has => [
        subject_class   => { is => 'UR::Object::Type', id_by => 'subject_class_name' },
        subject_id      => { is => 'SCALAR', is_optional => 1 },
        subject         => { is => 'UR::Object', 
                                calculate_from => ['subject_class_name','subject_id'],
                                calculate => '$subject_class_name->get($subject_id)' },
        aspect          => { is => 'String', is_optional => 1 },
        priority        => { is => 'Number', is_optional => 1, default_value => 1 },
        note            => { is => 'String', is_optional => 1 },
    ],
    is_transactional => 1,
);

# This is not implemented as a "real" observer via create() because at the point during bootstrapping
# that this module is loaded, we're not yet ready to start creating objects
__PACKAGE__->_insert_record_into_all_change_subscriptions('UR::Observer', 'priority', '',
                                          [\&_modify_priority, '', 0, UR::Object::Type->autogenerate_new_object_id_uuid]);

sub create {
    my $class = shift;

    $class->_create_or_define('create', @_);
}

sub __define__ {
    my $class = shift;

    $class->_create_or_define('__define__', @_);
}

sub _create_or_define {
    my $class = shift;
    my $method = shift;

    my ($rule,%extra) = UR::BoolExpr->resolve($class,@_);
    my $callback = delete $extra{callback};
    unless ($callback) {
        $class->error_message("'callback' is a required parameter for creating UR::Observer objects");
        return;
    }
    if (%extra) {
        $class->error_message("Cannot create observer.  Class $class has no property ".join(',',keys %extra));
        return;
    }

    my $subject_class_name = $rule->value_for('subject_class_name');
    my $aspect = $rule->value_for('aspect');
    my $subject_id = $rule->value_for('subject_id');
    unless ($subject_class_name->__meta__->_is_valid_signal($aspect)) {
        if ($subject_class_name->can('validate_subscription') and ! $subject_class_name->validate_subscription($aspect, $subject_id, $callback)) {
            $class->error_message("'$aspect' is not a valid aspect for class $subject_class_name");
            return;
        }
    }

    if (!defined($subject_class_name) or $subject_class_name eq 'UR::Object') { $subject_class_name = '' }; # This was part of the old API, not sure why it's still here?!
    if (!defined ($aspect)) { $aspect = '' };
    if (!defined ($subject_id)) { $subject_id = '' };

    my $self;
    if ($method eq 'create') {
        $self = $class->SUPER::create($rule);
    } elsif ($method eq '__define__') {
        $self = $class->SUPER::__define__($rule->params_list);
    } else {
        Carp::croak('Instantiating a UR::Observer with some method other than create() or __define__() is not supported');
    }
    $self->{callback} = $callback;

    my %params = $rule->params_list;
    my ($subscription, $delete_subscription);

    $self->_insert_record_into_all_change_subscriptions($subject_class_name, $aspect, $subject_id,
                                                        [$callback, $self->note, $self->priority, $self->id]);

    return $self;
}


sub _insert_record_into_all_change_subscriptions {
    my($class,$subject_class_name, $aspect,$subject_id, $new_record) = @_;

    my $list = $UR::Context::all_change_subscriptions->{$subject_class_name}->{$aspect}->{$subject_id} ||= [];
    push @$list, $new_record;
}

sub _modify_priority {
    my($self, $aspect, $old_val, $new_val) = @_;

    my $subject_class_name = $self->subject_class_name;
    my $subject_aspect = $self->aspect;
    my $subject_id = $self->subject_id;

    my $list = $UR::Context::all_change_subscriptions->{$subject_class_name}->{$subject_aspect}->{$subject_id};
    return unless $list;  # this is probably an error condition

    my $data;
    for (my $i = 0; $i < @$list; $i++) {
        if ($list->[$i]->[3] eq $self->id) {
            ($data) = splice(@$list,$i, 1);
            last;
        }
    }
    return unless $data;  # This is probably an error condition...

    $data->[2] = $new_val;

    $self->_insert_record_into_all_change_subscriptions($subject_class_name, $subject_aspect, $subject_id, $data);
}

sub callback {
    shift->{callback};
}

sub subscription {
    shift->{subscription}
}

sub delete {
    my $self = shift;
    #$DB::single = 1;

    my $subject_class_name = $self->subject_class_name;
    my $subject_id         = $self->subject_id;
    my $aspect             = $self->aspect;

    $subject_class_name = '' if (! $subject_class_name or $subject_class_name eq 'UR::Object');
    $subject_id         = '' unless (defined $subject_id);
    $aspect             = '' unless (defined $aspect);

    my $arrayref = $UR::Context::all_change_subscriptions->{$subject_class_name}->{$aspect}->{$subject_id};
    if ($arrayref) {
        my $index = 0;
        while ($index < @$arrayref) {
            if ($arrayref->[$index]->[3] eq $self->id) {
                my $found = splice(@$arrayref,$index,1);

                if (@$arrayref == 0)
                {
                    $arrayref = undef;

                    delete $UR::Context::all_change_subscriptions->{$subject_class_name}->{$aspect}->{$subject_id};
                    if (keys(%{ $UR::Context::all_change_subscriptions->{$subject_class_name}->{$aspect} }) == 0)
                    {
                        delete $UR::Context::all_change_subscriptions->{$subject_class_name}->{$aspect};
                    }
                }

                # old API
                unless ($subject_class_name eq '' || $subject_class_name->inform_subscription_cancellation($aspect,$subject_id,$self->{'callback'})) {
                    Carp::confess("Failed to validate requested subscription cancellation for aspect '$aspect' on class $subject_class_name");
                }

                # Return a ref to the callback removed.  This is "true", but better than true.
                #return $found;
                last;

            } else {
                # Increment only if we did not splice-out a value.
                $index++;
            }
        }
    }
    $self->SUPER::delete();
}

sub get_with_special_parameters {
    my($class,$rule,%extra) = @_;

    my $callback = delete $extra{'callback'};
    if (keys %extra) {
        Carp::croak("Unrecognized parameters in get(): " . join(', ', keys(%extra)));
    }
    my @matches = $class->get($rule);
    return grep { $_->callback eq $callback } @matches;
}

1;


=pod

=head1 NAME

UR::Observer - bind callbacks to object changes 

=head1 SYNOPSIS

    $rocket = Acme::Rocket->create(
        fuel_level => 100
    );
    
    $observer = $rocket->add_observer(
        aspect => 'fuel_level',
        callback => 
            sub {
                print "fuel level is: " . shift->fuel_level . "\n"
            },
    );

    for (3 .. 0) {
        $rocket->fuel_level($_);
    }
    # fuel level is: 3
    # fuel level is: 2
    # fuel level is: 1
    # fuel level is: 0
    
    $observer->delete;

=cut

