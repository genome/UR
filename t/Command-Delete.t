#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use TestEnvCrud;

use Test::Exception;
use Test::More tests => 3;

my %test;
subtest 'setup' => sub{
    plan tests => 4;

    use_ok('Command::Delete') or die;
    use_ok('Command::Crud') or die;

    my %sub_command_configs = map { $_ => { skip => 1 } } grep { $_ ne 'delete' } Command::Crud->buildable_sub_command_names;
    Command::Crud->create_command_subclasses(
        target_class => 'Test::Person',
        sub_command_configs => \%sub_command_configs,
    );

    $test{cmd} = 'Test::Person::Command::Delete';
    ok(UR::Object::Type->get($test{cmd}), 'person delete command exists'),

    $test{obj} = Test::Person->create(name => 'don');
    ok($test{obj}, 'create person');

};

subtest 'command properties' => sub{
    plan tests => 2;

    my $cmd = $test{cmd}->create;
    is($cmd->namespace, 'Test::Person::Command', 'namepace');
    is($cmd->target_name_ub, 'test_person', 'target_name_ub');
    $cmd->delete;

};

subtest 'delete' => sub{
    plan tests => 3;

    lives_ok(sub{ $test{cmd}->execute(test_person => $test{obj}); }, 'delete');
    my $person = Test::Person->get(name => 'don');
    ok(!$person, 'delete person');

    ok(UR::Context->commit, 'commit');

};

done_testing();
