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

plan tests => 27;

my $cmd = UR::Namespace::Command::Sys::ClassBrowser->create(
                namespace_name => 'Testing',
            );
ok($cmd, 'Created ClassBrowser command');

print "namespace module_directory is ",Testing->__meta__->module_directory,"\n";
exit;
my $by_class_name = $cmd->_generate_class_name_cache('Testing');
my $base_dir = File::Basename::dirname(__FILE__);

my %expected_class_data = (
                Testing => {
                    __class_name=> 'Testing',
                    __is        => ['UR::Namespace'],
                    __path      => $base_dir.'/test_namespace/Testing.pm',
                },
                'Testing::Something' => {
                    __class_name => 'Testing::Something',
                    __is        => ['UR::Object'],
                    __path      => $base_dir.'/test_namespace/Testing/Something.pm',
                },
                'Testing::Something::SubClass1' => {
                    __class_name => 'Testing::Something::SubClass1',
                    __is        => ['Testing::Something'],
                    __path      => $base_dir.'/test_namespace/Testing/Something/SubClass1.pm',
                },
                'Testing::Something::SubClass2' => {
                    __class_name => 'Testing::Something::SubClass2',
                    __is        => ['Testing::Something'],
                    __path      => $base_dir.'/test_namespace/Testing/Something/SubClass2.pm',
                },
                'Testing::Color' => {
                    __class_name=> 'Testing::Color',
                    __is        => ['UR::Object'],
                    __path      => $base_dir.'/test_namespace/Testing/Color.pm',
                },
            );

is_deeply($by_class_name, \%expected_class_data, '_generate__class_name_cache');

ok( $cmd->_load_class_info_from_modules_on_filesystem('Testing') ,'_load_class_info_from_modules_on_filesystem');

my $path_data = $cmd->class_info_for_pathname('Testing');
ok($path_data->{test_namespace}, "pathname 'test_namespace' is present at Testing namespace's root");

$path_data = $cmd->class_info_for_pathname('Testing', 'test_namespace/Testing');
is($path_data->{__path}, 'test_namespace/Testing', 'pathname "test_namespace/Testing" is present');
ok($path_data->{__is_dir}, '"test_namespace/Testing" is a directory');

$path_data = $cmd->class_info_for_pathname('Testing', 'test_namespace/Testing/Something/SubClass1.pm');
is_deeply($path_data, $expected_class_data{'Testing::Something::SubClass1'}, 'Found class data at "test_namespace/Testing/Something/SubClass1.pm"');

ok(! $cmd->class_info_for_pathname('Testing', 'test_namespace/does/not/exist'), 'non-existent pathname returns false');
