#!/usr/bin/env perl

use Test::More tests => 2;
use above "URT"; 
use strict;
use warnings;

# make sure things being associated with objects
# are not being copied in the constructor

use_ok("URT::33Subclass");

my $st = URT::33Subclass->create();

ok($st,"made subclass");

