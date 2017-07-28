#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use TestEnvCrud;

use Test::More tests => 1;

use_ok('Command::Crud') or die;

done_testing();
