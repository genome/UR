#!/usr/bin/env perl

use Test::More;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';
use UR;


my $dir = $INC{"UR.pm"};
$dir = File::Basename::dirname($dir);


@src = 
    map { chomp $_; s|/|::|g; s/.pm//; "use $_;" }
    sort
    grep { $_ !~ /UR\/All.pm/ }
    grep { /.pm$/ }
    `cd $dir; find *`; 

plan tests => scalar(@src);

for $src (@src) {
    eval $src;
    ok(!$@, "'$src' works");    
}

note( "Testing UR $UR::VERSION, Perl $], $^X" );

