#!/usr/bin/env perl

use Test::More;
use above "URT"; 
use strict;
use warnings;

plan skip_all => "known broken - fix in the future";
#plan tests => 2;

# make sure things being associated with objects
# are not being copied in the constructor

use_ok("URT::34Subclass");

my $st = URT::34Subclass->create();

ok($st,"made subclass");

