#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use Path::Class 'file';
use lib file(__FILE__)->dir->parent->parent->parent->parent->subdir("lib")->absolute->stringify;
use lib file(__FILE__)->dir->absolute->stringify;

use TestEnvCrud;
use Test::Exception;
use Test::More tests => 3;

my %test;
subtest 'setup' => sub{
    plan tests => 6;

    use_ok('UR::Object::Command::Delete') or die;
    use_ok('UR::Object::Command::Crud') or die;

    my %sub_command_configs = map { $_ => { skip => 1 } } grep { $_ ne 'delete' } UR::Object::Command::Crud->buildable_sub_command_names;
    UR::Object::Command::Crud->create_command_subclasses(
        target_class => 'Test::Muppet',
        sub_command_configs => \%sub_command_configs,
    );

    $test{cmd_class} = 'Test::Muppet::Command';
    ok(UR::Object::Type->get($test{cmd_class}), 'muppet command exists'),
    $test{cmd} = $test{cmd_class}.'::Delete';
    ok(UR::Object::Type->get($test{cmd}), 'muppet delete command exists'),
    is_deeply([$test{cmd_class}->sub_command_classes], [$test{cmd}], 'only generated delete command');

    $test{elmo} = Test::Muppet->create(name => 'elmo');
    ok($test{elmo}, 'create elmo');

};

subtest 'command properties' => sub{
    plan tests => 2;

    my $cmd = $test{cmd}->create;
    is($cmd->namespace, 'Test::Muppet::Command', 'namepace');
    is($cmd->target_name_ub, 'test_muppet', 'target_name_ub');
    $cmd->delete;

};

subtest 'delete' => sub{
    plan tests => 3;

    lives_ok(sub{ $test{cmd}->execute(test_muppet => $test{elmo}); }, 'delete');
    my $muppet = Test::Muppet->get(name => 'elmo');
    ok(!$muppet, 'delete muppet');

    ok(UR::Context->commit, 'commit');

};

done_testing();
