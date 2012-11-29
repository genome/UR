#!/usr/bin/env perl
use File::Basename;
use Test::More;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

plan tests => 4;
use UR;
my $x = 1;
my $sentry = UR::Util::on_destroy { $x = 2 };
is($x, 1, "value is 1 when the sentry has not been destroyed");
$sentry = undef;
is($x, 2, "value is 2 when the sentry has been destroyed");

$x = 1;
sub foo {
    my $sentry = UR::Util::on_destroy { $x = 3 };
    is($x, 1, "value is 1 while the sentry is still in scope");
}
foo();
is($x, 3, "value is 2 after the sentry goes out of scope");
