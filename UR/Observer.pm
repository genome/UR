
package UR::Observer;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    has => [
        subject_class   => { is => 'UR::Object::Type', id_by => 'subject_class_name' },
        subject_id      => { is => 'SCALAR', is_optional => 1 },
        subject         => { is => 'UR::Object', 
                                calculate_from => ['subject_class_name','subject_id'],
                                calculate => '$subject_class_name->get($subject_id)' },
        aspect          => { is => 'String' },
    ],
    is_transactional => 1,
);

sub create {
    my $class = shift;
    my ($rule,%extra) = $class->get_rule_for_params(@_);
    my $callback = delete $extra{callback};
    if (%extra) {
        die("Odd params!?" . Data::Dumper::Dumper(\%extra));
    }
    unless ($callback) {
        die "No callback supplied to observer!";
    }
    my $self = $class->SUPER::create($rule);
    $self->{callback} = $callback;

    my %params = $rule->params_list;
    my $subscription = $self->subject_class_name->create_subscription(
        id => $self->subject_id,
        method => $self->aspect,
        callback => $callback,
        note => "$self",
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
    $DB::single = 1;
    $self->subject_class_name->cancel_change_subscription(
        $self->subject_id,
        $self->aspect,
        $self->callback,
        "$self",
    );
    $self->SUPER::delete();
}

=pod

=head1




=cut

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

