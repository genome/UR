#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 1;
use Test::Exception;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";

use URT; # dummy namespace

my @data_sources = qw(UR::DataSource::Default URT::DataSource::SomeSQLite URT::DataSource::SomeFile URT::DataSource::SomeOracle);

#Default DataSource must be last
#Oracle can_savepoint, so its DataSource should come after the others
#Other DataSources should be sorted on name
my @expected_order = @data_sources[2,1,3,0];

my @ordered_data_sources = UR::Context::_order_data_sources_for_saving(@data_sources);

is_deeply(\@ordered_data_sources, \@expected_order, 'datasources are ordered as expected');
