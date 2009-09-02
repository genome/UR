#!/usr/bin/env perl
use strict;
use warnings;
use Test::More skip_all => "enable after configuring Oracle";

use URT; # dummy namespace

my $dbh = URT::DataSource::SomeOracle->get_default_dbh;
ok($dbh, "got a handle");

1;
