#!/usr/bin/env perl
use File::Basename;
use Test::More;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

sub dummy { eval{} };

plan tests => 4;
use UR;

subtest basic => sub {
    plan tests => 2;

    my $x = 1;
    my $sentry = UR::Util::on_destroy { $x = 2; dummy() };
    is($x, 1, "value is not updated when the sentry has not been destroyed");
    $sentry = undef;
    is($x, 2, "value is updated when the sentry has been destroyed");
};

subtest scope => sub {
    plan tests => 2;

    my $x = 1;
    my $foo = sub {
        my $sentry = UR::Util::on_destroy { $x = 3; dummy(); };
        is($x, 1, "value is not updated while the sentry is still in scope");
    };
    $foo->();
    is($x, 3, "value is updated after the sentry goes out of scope");
};

subtest exception => sub {
    plan tests => 3;

    my $x = 1;
    my $bar = sub {
        my $sentry = UR::Util::on_destroy { $x = 4; dummy(); };
        is($x, 1, "value is updated while the sentry is still in scope");
        die "ouch";
    };
    eval {
        $bar->();
    };
    my $exception = $@;
    is($x, 4, "value is updated after the sentry goes out of scope during thrown exception");
    ok($@, "exception is passed through even thogh the sentry does an eval internally: $@");
};

subtest cancel => sub {
    plan tests => 2;

    my $x = 1;
    do {
        my $sentry = UR::Util::on_destroy { $x = 2; };
        ok($sentry->cancel(), 'Cancel sentry');
    };
    is($x, 1, 'Cancelled sentry did not run');
};
