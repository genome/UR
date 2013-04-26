#!/usr/bin/env perl

use Test::More;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../../lib";
use lib File::Basename::dirname(__FILE__)."/../../..";
use lib File::Basename::dirname(__FILE__)."/test_namespace/";
use UR;
use strict;
use warnings;

use Cwd;

plan tests => 11;

my $cmd = UR::Namespace::Command::Sys::ClassBrowser->create(
                namespace_name => 'Testing',
            );
ok($cmd, 'Created ClassBrowser command');

my $by_class_name = $cmd->_generate_class_name_cache('Testing');
my $base_dir = File::Basename::dirname(__FILE__);

my %expected_class_data = (
                Testing => {
                    __name  => 'Testing',
                    __is    => ['UR::Namespace'],
                    __path  => $base_dir.'/test_namespace/Testing.pm',
                    __file  => 'Testing.pm',
                },
                'Testing::Something' => {
                    __name  => 'Testing::Something',
                    __is    => ['UR::Object'],
                    __path  => $base_dir.'/test_namespace/Testing/Something.pm',
                    __file  => 'Something.pm',
                },
                'Testing::Something::SubClass1' => {
                    __name  => 'Testing::Something::SubClass1',
                    __is    => ['Testing::Something'],
                    __path  => $base_dir.'/test_namespace/Testing/Something/SubClass1.pm',
                    __file  => 'SubClass1.pm',
                },
                'Testing::Something::SubClass2' => {
                    __name  => 'Testing::Something::SubClass2',
                    __is    => ['Testing::Something'],
                    __path  => $base_dir.'/test_namespace/Testing/Something/SubClass2.pm',
                    __file  => 'SubClass2.pm',
                },
                'Testing::Color' => {
                    __name  => 'Testing::Color',
                    __is    => ['UR::Object'],
                    __path  => $base_dir.'/test_namespace/Testing/Color.pm',
                    __file  => 'Color.pm',
                },
            );

is_deeply($by_class_name, \%expected_class_data, '_generate__class_name_cache');

ok( $cmd->_load_class_info_from_modules_on_filesystem('Testing') ,'_load_class_info_from_modules_on_filesystem');

my $path_data = $cmd->cache_info_for_pathname('Testing');
ok($path_data->{test_namespace}, "pathname 'test_namespace' is present at Testing namespace's root");
is($path_data->{test_namespace}->{__is_dir}, 1, 'It is a directory');
is($path_data->{test_namespace}->{__file}, 'test_namespace', '... file test_namespace');
is($path_data->{test_namespace}->{__name}, 'test_namespace', '... named test_namespace');

$path_data = $cmd->cache_info_for_pathname('Testing', 'test_namespace/Testing');
my @items = sort grep { m/^[^_]/} keys(%$path_data);
is(scalar(@items), 3, 'pathname "test_namespace/Testing" has 3 items');
is_deeply(\@items, [ qw( Color.pm Something Something.pm )], 'Expected contents');

$path_data = $cmd->cache_info_for_pathname('Testing', 'test_namespace/Testing/Something/SubClass1.pm');
is_deeply($path_data, $expected_class_data{'Testing::Something::SubClass1'}, 'Found class data at "test_namespace/Testing/Something/SubClass1.pm"');

ok(! $cmd->cache_info_for_pathname('Testing', 'test_namespace/does/not/exist'), 'non-existent pathname returns false');
