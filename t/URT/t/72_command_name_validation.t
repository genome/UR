#!/usr/bin/env perl

use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";

use UR;
use Test::More;

my @tests = ('WordWord', 'Word456Word', 'Word456aWord', '456Word', 'Word456', 'WWWord', '456');

plan tests => scalar(@tests);

for my $test (@tests) {

    my $self = 'Genome::' . $test;

    UR::Object::Type->define(
        class_name => $self,
        is => 'Command',
    );

    
    my $command_name = $self->command_name_brief($test);
    my $class_name = join("", map { ucfirst($_) } split(/-/, $command_name));
    is($class_name, $test, 'command/class symmetry for word style: ' . $test);
}
