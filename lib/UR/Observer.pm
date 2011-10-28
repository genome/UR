
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
    ],
    is_transactional => 1,
);

sub create {
    my $class = shift;
    my ($rule,%extra) = UR::BoolExpr->resolve($class,@_);
    my $callback = delete $extra{callback};
    if (%extra) {
        Carp::croak("Cannot create observer.  Class $class has no property ".join(',',keys %extra));
    }
    unless ($callback) {
        Carp::croak("'callback' argument is required for create()");
    }
    my $self = $class->SUPER::create($rule);
    $self->{callback} = $callback;

    my %params = $rule->params_list;
    my ($subscription, $delete_subscription);
    $subscription = $self->subject_class_name->create_subscription(
        id => $self->subject_id,
        method => $self->aspect,
        callback => $callback,
        note => "$self",
    );

    # because subscription is low level it is not deleted by the low level _abandon_object
    # but the delete signal is fired so we can cleanup with a subscription on delete
    # if someone adds there own delete signal we want to make sure ours gets run last
    my $delete_callback;
    $delete_callback = sub {
        # cancel original subscription
        $self->subject_class_name->cancel_change_subscription(
            $self->subject_id,
            $self->aspect,
            $self->callback,
            "$self",
        );
        # cancel our delete subscription
        $self->class->cancel_change_subscription(
            $self->id,
            'delete',
            $delete_callback,
            "$self",
        ); 
    };
    # create our delete subscription to cleanup if the observer gets deleted
    $delete_subscription = $self->class->create_subscription(
        id => $self->id,
        method => 'delete',
        callback => $delete_callback,
        note => "$self",
        priority => 1000, # "last"
    );

    return $self;
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
    $self->subject_class_name->cancel_change_subscription(
        $self->subject_id,
        $self->aspect,
        $self->callback,
        "$self",
    );
    $self->SUPER::delete();
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

