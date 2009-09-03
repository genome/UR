#!/usr/bin/env perl

use Test::More tests => 2;
use above "URT"; 
use strict;
use warnings;

my $o = URT::ObjWithHash->create(myhash1 => { aaa => 111, bbb => 222 }, myhash2 => [ ccc => 333, ddd => 444 ]); 
my @h = ($o->myhash1, $o->myhash2); 
diag "data was: " . Data::Dumper::Dumper($o,@h);
is(ref($h[0]),'HASH', "got an object back");
is(ref($h[1]),'ARRAY', "got an object back");
