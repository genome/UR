#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 1;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;             # dummy namespace

my $o = URT::Thingy->create(id => 111);
ok($o, "made an object");

1;
