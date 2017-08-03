#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use TestEnvCrud;

use Test::Exception;
use Test::More tests => 4;

my %test;
subtest 'setup' => sub{
    plan tests => 4;

    use_ok('Command::Create') or die;
    use_ok('Command::Crud') or die;

    my %sub_command_configs = map { $_ => { skip => 1 } } grep { $_ ne 'create' } Command::Crud->buildable_sub_command_names;
    Command::Crud->create_command_subclasses(
        target_class => 'Test::Person',
        sub_command_configs => \%sub_command_configs,
    );

    $test{cmd} = 'Test::Person::Command::Create';
    ok(UR::Object::Type->get($test{cmd}), 'person create command exists'),

    $test{mom} = Test::Person->create(name => 'mom');
    ok($test{mom}, 'create mom');

};

subtest 'command properties' => sub{
    plan tests => 2;

    my $cmd = $test{cmd}->create;
    is($cmd->namespace, 'Test::Person::Command', 'namepace');
    is($cmd->target_class, 'Test::Person', 'target_class');
    $cmd->delete;

};

subtest 'fails' => sub{
    plan tests => 1;

    my $cmd = $test{cmd}->create;
    ok(!$cmd->execute, 'fails w/o params');
    $cmd->delete;

};

subtest 'create' => sub{
    plan tests => 6;

    my %params = (
        name => 'me',
        title => 'mr',
        has_pets => 'no',
        mom => $test{mom},
    );
    lives_ok(sub{ $test{cmd}->execute(%params); }, 'create');

    my $new_person = Test::Person->get(name => 'me');
    ok($new_person, 'created new person');
    is($new_person->title, 'mr', 'title');
    is($new_person->has_pets, 'no', 'has_pets');
    is($new_person->mom, $test{mom}, 'mom');

    ok(UR::Context->commit, 'commit');

};

done_testing();
