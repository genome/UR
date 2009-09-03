#!/usr/bin/env perl
use strict;
use warnings;
use URT;
use Test::More tests => 5;

class Game::Card {
    has => [
        suit    => { is => 'Text', valid_values => [qw/heart diamond club spade/], },
        color   => { is => 'Text', valid_values => [qw/red blue green/], is_mutable => 0 },
    ],
};

for my $class (qw/Game::Card/) {

    my $c1 = $class->create(suit => 'spade', color => 'red');
    ok($c1, "created an object with a valid property");

    my @i1 = $c1->invalid;
    is(scalar(@i1), 0, "no cases of invalididy") 
        or diag(Data::Dumper::Dumper(\@i1));

    my $c2 = $class->create(suit => 'badsuit', color => 'blue');
    ok($c2, "created an object with an invalid property");

    my @i2 = $c2->invalid;
    is(scalar(@i2), 1, "one expected cases of invalididy") 
        or diag(Data::Dumper::Dumper(\@i2));

    $c2->suit('heart');
    @i2 = $c2->invalid;
    is(scalar(@i2), 0, "zero cases of invalididy after fix") 
        or diag(Data::Dumper::Dumper(\@i2));

    #my $c3 = eval { $class->create(suit => 'spade', color => 'badcolor') };
    #ok(!defined($c3), "correctly refused to create an object with an invalid immutable property")
    #    or diag(Data::Dumper::Dumper($c3));
}

