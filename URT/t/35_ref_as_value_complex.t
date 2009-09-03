#!/usr/bin/env perl

use Test::More tests => 12;
use above "URT"; 
use strict;
use warnings;

# make sure things being associated with objects
# are not being copied in the constructor

class TestClassB {
    has   => [
        value => { is => 'String' },
    ],
};

class TestClassA {
    has   => [
        b_thing => { is => 'TestClassB' }
    ],
};

my $ax = TestClassA->create();
ok($ax, "Created TestClassA without b_thing");

my $bx = TestClassB->create( value => 'abcdfeg' );
ok($bx, "Created TestClassB with value");

ok($ax->b_thing($bx), "Set b_thing to TestClassB object");
is($ax->b_thing, $bx, "b_thing is TestClassB object");

my $ay = TestClassA->create(
    b_thing => $bx
);
ok($ay, "Created TestClassA with bx as b_thing");
is($ax->b_thing,$ay->b_thing, "ax->b_thing is ay->b_thing");

ok($bx->value('oyoyoy'), "Changed bx->value");
is($ax->b_thing->value, $ay->b_thing->value, "ax->b_thing value is ay->b_thing value");

my $by = TestClassB->create( value => 'zzzykk' );
ok($by, "Created TestClassB with value");

ok($ay->b_thing($by), "Changed ay b_thing to by");

isnt($ax->b_thing,$ay->b_thing,"ax b_thing is not ay b_thing");
isnt($ax->b_thing->value,$ay->b_thing->value,"ax->b_thing value is not ay->b_thing value");

