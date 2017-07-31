#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use Path::Class;
use Test::More tests => 3;

use TestEnvCrud;

subtest 'paths' => sub{
    plan tests => 4;

    my $current_repo_path = TestEnv->current_repo_path;
    isa_ok($current_repo_path, 'Path::Class::Dir', 'current_repo_path set');
    ok(-d "$current_repo_path", 'current_repo_path exists');

    my $test_data_path = TestEnv->test_data_path;
    isa_ok($test_data_path, 'Path::Class::Dir', 'test_data_path set');

    my $test_data_dir = TestEnv->test_data_directory_for_package('Command::Awesome');
    is($test_data_dir, $test_data_path->subdir('Command-Awesome'), 'test_data_dir_for_package Command::Awesome');

};

subtest 'ENVs' => sub{
    plan tests => 2;

    ok($ENV{UR_DBI_NO_COMMIT}, 'no commit is on');
    ok($ENV{UR_USE_DUMMY_AUTOGENERATED_IDS}, 'use dummy ids is on');

};

subtest 'test classes' => sub{
    plan tests => 5;

    for my $class (qw/ Test::Person Test::Job Test::Relationship /) {
        my $meta = UR::Object::Type->get($class);
        ok($meta, "test $class meta");
    }

    can_ok('Test::Person', 'job');
    can_ok('Test::Person', 'relationships');

};

done_testing();
