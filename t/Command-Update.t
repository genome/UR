#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use TestEnvCrud;

use Test::Exception;
use Test::More tests => 5;

my %test;
subtest 'setup' => sub{
    plan tests => 7;

    use_ok('Command::Update') or die;
    use_ok('Command::Crud') or die;

    my %sub_command_configs = map { $_ => { skip => 1 } } grep { $_ ne 'update' } Command::Crud->buildable_sub_command_names;
    $sub_command_configs{update}->{only_if_null} = [qw/ best_friend title /];
    Command::Crud->create_command_subclasses(
        target_class => 'Test::Person',
        sub_command_configs => \%sub_command_configs,
    );

    $test{cmd1} = 'Test::Person::Command::Update::Title';
    ok(UR::Object::Type->get($test{cmd1}), 'person update name command exists'),

    $test{cmd2} = 'Test::Person::Command::Update::BestFriend';
    ok(UR::Object::Type->get($test{cmd2}), 'person update name command exists'),

    $test{person} = Test::Person->create(name => 'stan');
    ok($test{person}, 'create stan');

    $test{friend} = Test::Person->create(name => 'kyle');
    ok($test{friend}, 'create kyle');

    $test{job} = Test::Job->create(name => 'fourth grader');
    ok($test{job}, 'create job');

};

subtest 'command properties' => sub{
    plan tests => 3;

    my $cmd = $test{cmd1}->create;
    is($cmd->namespace, 'Test::Person::Command', 'namespace');
    is($cmd->target_name_pl, 'test persons', 'target_name_pl');
    is($cmd->target_name_ub_pl, 'test_persons', 'target_name_ub_pl');
    $cmd->delete;

};

subtest 'fails' => sub{
    plan tests => 2;

    my $cmd = $test{cmd1}->create;
    ok(!$cmd->execute, 'fails w/o params');
    $cmd->delete;

    my $cmd = $test{cmd1}->create(test_persons => [$test{person}]);
    ok(!$cmd->execute, 'fails w/o value');
    $cmd->delete;

};

subtest 'update' => sub{
    # This tests a direct property that has valid values and can only be udated if NULL
    plan tests => 9;

    my $cmd = $test{cmd1}->create(test_persons => [$test{person}], value => 'blah');
    ok(!$cmd->execute, 'udpate fails w/ invalid value');
    ok(!$test{person}->title, 'did not set title');
    $cmd->delete;
    ok(UR::Context->commit, 'commit');

    $cmd = $test{cmd1}->create(test_persons => [$test{person}], value => 'mr');
    ok($cmd->execute, 'udpate title');
    is($test{person}->title, 'mr', 'set title');
    ok(UR::Context->commit, 'commit');

    $cmd = $test{cmd1}->create(test_persons => [$test{person}], value => 'dr');
    ok($cmd->execute, 'udpate');
    is($test{person}->title, 'mr', 'did not set title b/c it was not null');
    ok(UR::Context->commit, 'commit');

};

subtest 'update via property' => sub{
    # This tests 'best friend' a via property that can only be udated if NULL
    plan tests => 6;

    my $cmd = $test{cmd2}->create(test_persons => [$test{person}], value => $test{friend});
    ok($cmd->execute, 'udpate best_friend');
    is($test{person}->best_friend, $test{friend}, 'set best_friend');
    ok(UR::Context->commit, 'commit');

    $cmd = $test{cmd2}->create(test_persons => [$test{person}], value => $test{person});
    ok($cmd->execute, 'udpate');
    print Data::Dumper::Dumper($test{person}->best_friend);
    is($test{person}->best_friend, $test{friend}, 'did not set best_friend b/c it was not null');
    ok(UR::Context->commit, 'commit');

};

done_testing();
