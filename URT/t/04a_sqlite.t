#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 2;

use URT; # dummy namespace

my $dbh = URT::DataSource::SomeSQLite->get_default_handle;
ok($dbh, "got a handle");
isa_ok($dbh, 'UR::DBI::db', 'Returned handle is the proper class');

unlink URT::DataSource::SomeSQLite->server;

1;
