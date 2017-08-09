#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use TestEnvCrud;

use Test::Exception;
use Test::More tests => 7;

my %test;
subtest 'setup' => sub{
    plan tests => 9;

    use_ok('UR::Object::Command::Update') or die;
    use_ok('UR::Object::Command::Crud') or die;

    my %sub_command_configs = map { $_ => { skip => 1 } } grep { $_ ne 'update' } UR::Object::Command::Crud->buildable_sub_command_names;
    $sub_command_configs{update}->{only_if_null} = [qw/ best_friend name /];
    UR::Object::Command::Crud->create_command_subclasses(
        target_class => 'Test::Muppet',
        sub_command_configs => \%sub_command_configs,
    );

    $test{cmd_class} = 'Test::Muppet::Command';
    ok(UR::Object::Type->get($test{cmd_class}), 'muppet command exists'),
    $test{cmd} = $test{cmd_class}.'::Update';
    ok(UR::Object::Type->get($test{cmd}), 'muppet update command exists'),
    is_deeply([$test{cmd_class}->sub_command_classes], [$test{cmd}], 'only generated update command');

    $test{ernie} = Test::Muppet->create(name => 'ernie');
    ok($test{ernie}, 'create ernie');

    $test{burt} = Test::Muppet->create(name => 'burt');
    ok($test{burt}, 'create burt');

    $test{gonzo} = Test::Muppet->create(name => 'gonzo');
    ok($test{gonzo}, 'create gonzo');

    $test{job} = Test::Job->create(name => 'troublemaker');
    ok($test{job}, 'create job');

};

subtest 'command properties' => sub{
    plan tests => 3;

    my $cmd = Test::Muppet::Command::Update::Name->create;
    is($cmd->namespace, 'Test::Muppet::Command', 'namespace');
    is($cmd->target_name_pl, 'test muppets', 'target_name_pl');
    is($cmd->target_name_ub_pl, 'test_muppets', 'target_name_ub_pl');
    $cmd->delete;

};

subtest 'update name' => sub{
    plan tests => 6;

    my $pkg = 'Test::Muppet::Command::Update::Name';
    ok(UR::Object::Type->get($pkg), 'muppet update name command exists'),

    my $cmd = $pkg->create;
    ok(!$cmd->execute, 'fails w/o params');
    $cmd->is_executed(undef);

    $cmd->test_muppets([$test{ernie}]);
    ok(!$cmd->execute, 'fails w/o value');

    $cmd->value('blah');
    ok($cmd->execute, 'udpate fails b/c name is not null');
    is($test{ernie}->name, 'ernie', 'did not set title b/c it was not null');
    ok(UR::Context->commit, 'commit');

};

subtest 'update title' => sub{
    plan tests => 8;

    my $pkg = 'Test::Muppet::Command::Update::Title';
    ok(UR::Object::Type->get($pkg), 'muppet update title command exists'),

    my $cmd = $pkg->create;
    ok(!$cmd->execute, 'fails w/o params');
    $cmd->is_executed(undef);

    $cmd->test_muppets([$test{ernie}]);
    ok(!$cmd->execute, 'fails w/o value');
    $cmd->is_executed(undef);

    $cmd->value('blah');
    ok(!$cmd->execute, 'udpate fails w/ invalid value');
    ok(!$test{ernie}->title, 'did not set title');
    $cmd->is_executed(undef);

    $cmd->value('mr');
    ok($cmd->execute, 'udpate title');
    is($test{ernie}->title, 'mr', 'set title');
    ok(UR::Context->commit, 'commit');

};

subtest 'update best friend' => sub{
    plan tests => 9;

    my $pkg = 'Test::Muppet::Command::Update::BestFriend';
    ok(UR::Object::Type->get($pkg), 'muppet update best friend command exists'),

    my $cmd = $pkg->create;
    ok(!$cmd->execute, 'fails w/o params');
    $cmd->is_executed(undef);

    $cmd->test_muppets([$test{ernie}]);
    ok(!$cmd->execute, 'fails w/o value');
    $cmd->is_executed(undef);

    $cmd->value($test{burt});
    ok($cmd->execute, 'udpate best_friend');
    is($test{ernie}->best_friend, $test{burt}, 'set best_friend');
    ok(UR::Context->commit, 'commit');

    $cmd = $pkg->create(test_muppets => [$test{ernie}], value => $test{ernie});
    ok($cmd->execute, 'udpate');
    is($test{ernie}->best_friend, $test{burt}, 'did not set best_friend b/c it was not null');
    ok(UR::Context->commit, 'commit');

};

subtest 'update job' => sub{
    plan tests => 7;

    my $pkg = 'Test::Muppet::Command::Update::Job';
    ok(UR::Object::Type->get($pkg), 'muppet update job command exists'),

    my $cmd = $pkg->create;
    ok(!$cmd->execute, 'fails w/o muppets');
    $cmd->is_executed(undef);

    $cmd->test_muppets([$test{ernie}]);
    ok(!$cmd->execute, 'fails w/o value');
    $cmd->is_executed(undef);

    ok(!$test{ernie}->job, 'ernie does not have a job');
    $cmd->value($test{job});
    ok($cmd->execute, 'udpate job');
    is($test{ernie}->job, $test{job}, 'set job');
    ok(UR::Context->commit, 'commit');

};

subtest 'fails' => sub{
   plan tests => 2;

    my $cmd = Test::Muppet::Command::Update::Name->create;
    ok(!$cmd->execute, 'fails w/o muppets');
    $cmd->is_executed(undef);

    $cmd->test_muppets([$test{ernie}]);
    ok(!$cmd->execute, 'fails w/o value');
    $cmd->delete;

};

done_testing();
