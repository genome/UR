#!/usr/bin/env perl

use Test::More;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

plan tests => 2;
use_ok( 'UR' );
use_ok( 'UR::All' );
note( "Testing UR $UR::VERSION, Perl $], $^X" );

