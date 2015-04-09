#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;
use Test::Fatal qw(exception);

use UR qw();

subtest 'class initialization' => sub {
    plan tests => 4;

    subtest 'default_value and default_from are incompatible' => sub {
        plan tests => 2;
        my %thing = (
            class_name => 'URT::Thing',
            has => [
                name => {
                    is => 'String',
                    default_value => 'foo',
                    default_from => 1,
                },
            ],
        );
        local *URT::Thing::__default_name__ = sub { 'some name' };
        my $exception = exception { UR::Object::Type->define(%thing) };
        ok($exception, 'got an exception when trying to use `default_value` and `default_from`');

        delete $thing{has}->[1]->{default_value};
        $exception = exception { UR::Object::Type->define(%thing) };
        ok(!$exception, 'did not get an exception when trying to use just `default_from`')
            or diag $exception;
    };

    subtest 'default_from validates method name' => sub {
        plan tests => 2;
        my %thing = (
            class_name => 'URT::Thing',
            has => [
                name => {
                    is => 'String',
                    default_from => 'some_method',
                },
            ],
        );
        my $exception = exception { UR::Object::Type->define(%thing) };
        ok($exception, 'got an exception when trying to use `default_from` without method defined');

        local *URT::Thing::some_method = sub { 'some name' };
        $exception = exception { UR::Object::Type->define(%thing) };
        ok(!$exception, 'did not get an exception when trying to use `default_from` with method defined')
            or diag $exception;
    };

    subtest 'default_from => 1 defaults to __default_PROP__' => sub {
        plan tests => 2;
        my %thing = (
            class_name => 'URT::Thing',
            has => [
                name => {
                    is => 'String',
                    default_from => 1,
                },
            ],
        );
        my $exception = exception { UR::Object::Type->define(%thing) };
        ok($exception, 'got an exception when trying to use `default_from` without method defined');

        local *URT::Thing::__default_name__ = sub { 'some name' };
        $exception = exception { UR::Object::Type->define(%thing) };
        ok(!$exception, 'did not get an exception when trying to use `default_from` with method defined')
            or diag $exception;
    };

    subtest 'default_from supports coderef' => sub {
        plan tests => 2;
        my %thing = (
            class_name => 'URT::Thing',
            has => [
                name => {
                    is => 'String',
                    default_from => sub { 'some name' },
                },
            ],
        );
        my $exception = exception { UR::Object::Type->define(%thing) };
        ok(!$exception, 'did not get an exception when trying to use `default_from` with method defined')
            or diag $exception;

        my $thing = URT::Thing->create();
        is($thing->name, 'some name', 'got default name');
    };
};

subtest 'dynamic default values' => sub {
    plan tests => 4;

    my $orig_foo = 'A';
    my $foo = $orig_foo;
    local *URT::ThingWithDefaultSub::__default_name__ = sub { $foo };
    UR::Object::Type->define(
        class_name => 'URT::ThingWithDefaultSub',
        has => [
            name => { is => 'String', default_from => 1 },
        ],
    );

    my $thing1 = URT::ThingWithDefaultSub->create();
    is($thing1->name, $foo, 'thing1 default name was resolved');

    $foo++;
    isnt($foo, $orig_foo, 'foo was changed');

    my $thing2 = URT::ThingWithDefaultSub->create();
    is($thing2->name, $foo, 'thing2 default name was resolved');

    isnt($thing1->name, $thing2->name, 'things have different names');
};
