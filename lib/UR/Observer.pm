
package UR::Observer;

use strict;
use warnings;

require UR;
our $VERSION = "0.43"; # UR $VERSION;

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
        once            => { is => 'Boolean', is_optional => 1, default_value => 0 },
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
    my %params = @_;

    my $callback = delete $params{callback};
    unless ($callback) {
        $class->error_message("'callback' is a required parameter for creating UR::Observer objects");
        return;
    }

    my $subject_class_name = $params{subject_class_name};
    my $subject_class_meta = eval { $subject_class_name->__meta__ };
    if ($@) {
        $class->error_message("Can't create observer with subject_class_name '$subject_class_name': Can't get class metadata for class '$subject_class_name': $@");
        return;
    }
    unless ($subject_class_meta) {
        $class->error_message("Class $subject_class_name cannot be the subject class for an observer because there is no class metadata");
        return;
    }

    my $aspect = $params{aspect};
    my $subject_id = $params{subject_id};
    unless ($subject_class_meta->_is_valid_signal($aspect)) {
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
        $self = $class->SUPER::create(%params);
    } elsif ($method eq '__define__') {
        $self = $class->SUPER::__define__(%params);
    } else {
        Carp::croak('Instantiating a UR::Observer with some method other than create() or __define__() is not supported');
    }
    $self->{callback} = $callback;
    $self->_insert_record_into_all_change_subscriptions($subject_class_name, $aspect, $subject_id,
                                                        [$callback, $self->note, $self->priority, $self->id, $self->once]);

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
        priority => 2,
    );

    $observer2 = UR::Observer->create(
        subject_class => 'Acme::Rocket',
        subject_id    => $rocket->id,
        aspect => 'fuel_level',
        callback =>
            sub {
                my($self,$changed_aspect,$old_value,$new_value) = @_;
                if ($new_value == 0) {
                    print "Bail out!\n";
                }
            },
        priority => 0
    );


    for (3 .. 0) {
        $rocket->fuel_level($_);
    }
    # fuel level is: 3
    # fuel level is: 2
    # fuel level is: 1
    # Bail out!
    # fuel level is: 0
    
    $observer->delete;

=head1 DESCRIPTION

UR::Observer implements the observer pattern for UR objects.  These observers
can be attached to individual object instances, or to whole classes.  They
can send notifications for changes to object attributes, or to other state
changes such as when an object is loaded from its datasource or deleted.

=head1 CONSTRUCTOR

Observers can be created either by using the method C<add_observer()> on
another class, or by calling C<create()> on the UR::Observer class.

  my $o1 = Some::Other::Class->add_observer(...);
  my $o2 = $object_instance->add_observer(...);
  my $o3 = UR::Observer->create(...);

The constructor accepts these parameters:

=over 2

=item subject_class_name

The name of the class the observer is watching.  If this observer is being
created via C<add_observer()>, then it figures out the subject_class_name
from the class or object it is being called on.

=item subject_id

The ID of the object the observer is watching.  If this observer is being
created via C<add_observer()>, then it figures out the subject_id from the
object it was called on.  If C<add_observer()> was called as a class method,
then subject_id is omitted, and means that the observer should fire for
changes on any instance of the class or sub-class.

=item priority

A numeric value used to determine the order the callbacks are fired.  Lower
numbers are higher priority, and are run before callbacks with a numerically
higher priority.  The default priority is 1.  Negative numbers are ok.

=item aspect

The attribute the observer is watching for changes on.  The aspect is commonly
one of the properties of the class.  In this case, the callback is fired after
the property's value changes.  aspect can be omitted, which means the observer
should fire for any change in the object state.  If both subject_id and aspect
are omitted, then the observer will fire for any change to any instance of the
class.

There are other, system-level aspects that can be watched for that correspond to other types
of state change:

=over 2

=item create

After a new object instance is created

=item delete

After an n object instance is deleted

=item load

After an object instance is loaded from its data source

=item commit

After an object instance has changes saved to its data source

=back

=item callback

A coderef that is called after the observer's event happens.  The coderef is
passed four parameters: $self, $aspect, $old_value, $new_value.  In this case,
$self is the object that is changing, not the UR::Observer instance (unless,
of course, you have created an observer on UR::Observer).  The return value of
the callback is ignored.

=item once

If the 'once' attribute is true, the observer is deleted immediately after
the callback is run.  This has the effect of running the callback only once,
no matter how many times the observer condition is triggered.

=item note

A text string that is ignored by the system

=back

=head2 Custom aspects

You can create an observer for an aspect that is neither a property nor one
of the system aspects by listing the aspect names in the metadata for the
class.

    class My::Class {
        has => [ 'prop_a', 'another_prop' ],
        valid_signals => ['custom', 'pow' ],
    };

    my $o = My::Class->add_observer(
                aspect => 'pow',
                callback => sub { print "POW!\n" },
            );
    My::Class->__signal_observers__('pow');  # POW!

    my $obj = My::Class->create(prop_a => 1);
    $obj->__signal_observers__('custom');  # not an error

To help catch typos, creating an observer for a non-standard aspect generates
an error message but not an exception, unless the named aspect is in the
list of 'valid_signals' in the class metadata.  Nothing in the system will
trigger these observers, but they can be triggered in your own code using the
C<__signal_observers()__> class or object method.  Sending a signal for an
aspect that no observers are watching for is not an error.

=cut

