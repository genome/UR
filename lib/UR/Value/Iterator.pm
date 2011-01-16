package UR::Value::Iterator;

use strict;
use warnings;
require UR;
our $VERSION = "0.27"; # UR $VERSION;

sub create {
    my $class = shift;
    my $set = $class->define_set(@_);
    my @members = $set->members;
    return $class->create_for_value_arrayref(\@members);
}

sub create_for_value_arrayref {
    my ($class, $arrayref) = @_;
    return bless { members => $arrayref }, $class;
}

sub next {
    shift @{ shift->{members} };
}

1;

