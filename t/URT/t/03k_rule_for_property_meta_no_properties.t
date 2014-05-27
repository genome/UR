#!/usr/bin/env perl

use strict;
use warnings;

use UR;
use Test::More tests => 2;
use Test::Exception;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;

class My::Foo {
    attributes_have => [
        is_blah => { is => 'Boolean' },
    ],
};

my $meta = My::Foo->__meta__;
my @p;

lives_ok(sub {@p = $meta->properties(is_blah => 1)});
is(scalar(@p), 0, "didn't get any properties");
