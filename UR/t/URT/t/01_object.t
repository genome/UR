#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 1;

use URT;             # dummy namespace
use URT::Thingy;   # dummy class

my $o = URT::Thingy->create(id => 111);
ok($o, "made an object");

1;
