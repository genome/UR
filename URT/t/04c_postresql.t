#!/usr/bin/env perl
use strict;
use warnings;
use Test::More skip_all => "enable after configuring PostgreSQL";

use URT; # dummy namespace

my $dbh = URT::DataSource::SomePostgreSQL->get_default_dbh;
ok($dbh, "got a handle");

1;
