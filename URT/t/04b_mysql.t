#!/usr/bin/env perl
use strict;
use warnings;

use Test::More skip_all => "enable after configuring MySQL";
use URT;

my $dbh = URT::DataSource::SomeMySQL->get_default_dbh;
ok($dbh, "got a handle");

1;
