#!/usr/bin/env perl 

use strict;
use warnings;
use Test::More;

my $symlink;
BEGIN {
    require Cwd;
    require File::Basename;
    my $dir = Cwd::abs_path(File::Basename::dirname(__FILE__) . '/../../');
    $symlink = $dir . '-symlink';
    unlink($symlink) if (-e $symlink);
    is(system("ln -s $dir $symlink"), 0, "Created symlink'd lib for Slimspace namespace");
};
use lib $symlink;
use Slimspace;

my $path = $INC{'Slimspace.pm'};
my $abs_path = Cwd::abs_path($path);
is($path, $abs_path, 'Loading a namespace resolves symlink');
is(unlink($symlink), 1, 'Removed symlink');

done_testing();
