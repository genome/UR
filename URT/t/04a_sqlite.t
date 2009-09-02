#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 1;

use URT; # dummy namespace

my $dbh = URT::DataSource::SomeSQLite->get_default_dbh;
ok($dbh, "got a handle");

1;
