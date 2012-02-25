package UR::Value::Text;

use strict;
use warnings;

require UR;
our $VERSION = "0.37"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::Text',
    is => ['UR::Value'],
);

use overload (
    '.' => \&concat,
    '""' => \&stringify,
    fallback => 1,
);

sub swap {
    my ($a, $b) = @_;
    return ($b, $a);
}

sub concat {
    my ($self, $other, $swap) = @_;
    my $class = ref $self;
    $self = $self->id;
    ($self, $other) = swap($self, $other) if $swap;
    return $class->get($self . $other);
}

sub stringify {
    my $self = shift;
    return $self->id;
}

1;
