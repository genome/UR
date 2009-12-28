#!/usr/bin/env perl

use Test::More;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

if ($ENV{UR_MOOSE}) { 
    plan tests => 1;
}
else {
    plan skip_all => ": only used when UR_MOOSE is set";
}
use_ok( 'UR' );

diag( "Testing UR $UR::VERSION, Perl $], $^X" );

