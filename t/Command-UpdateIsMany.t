#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use TestEnvCrud;

use Test::Exception;
use Test::More tests => 3;

my %test;
subtest 'setup' => sub{
    plan tests => 5;

    use_ok('Command::UpdateIsMany') or die;
    use_ok('Command::Crud') or die;

    my %sub_command_configs = map { $_ => { skip => 1 } } grep { $_ ne 'update' } Command::Crud->buildable_sub_command_names;
    Command::Crud->create_command_subclasses(
        target_class => 'Test::Muppet',
        sub_command_configs => \%sub_command_configs,
    );

    $test{ernie} = Test::Muppet->create(name => 'ernie');
    ok($test{ernie}, 'create ernie');

    $test{burt} = Test::Muppet->create(name => 'burt');
    ok($test{burt}, 'create burt');

    $test{gonzo} = Test::Muppet->create(name => 'gonzo');
    ok($test{gonzo}, 'create gonzo');

};

subtest 'add friend' => sub{
    plan tests => 9;

    my $pkg = 'Test::Muppet::Command::Update::Friends::Add';
    ok(UR::Object::Type->get($pkg), 'muppet add friends command exists'),

    my $cmd = $pkg->create;
    is($cmd->namespace, 'Test::Muppet::Command', 'namespace');
    is($cmd->property_function, 'add_friend', 'property_function');

    ok(!$cmd->execute, 'fails w/o params');
    $cmd->is_executed(undef);

    $cmd->test_muppets([$test{ernie}]);
    ok(!$cmd->execute, 'fails w/o value');
    $cmd->is_executed(undef);

    $test{ernie}->add_friend($test{burt});
    is_deeply([$test{ernie}->friends], [$test{burt}], 'ernie is friends with burt');
    $cmd->values([$test{gonzo}]);
    ok($cmd->execute, 'add friend');
    is_deeply([sort {$a->name cmp $b->name} $test{ernie}->friends], [sort {$a->name cmp $b->name} ($test{burt}, $test{gonzo})], 'ernie is friends with burt and gonzo');
    ok(UR::Context->commit, 'commit');

};

subtest 'remove friend' => sub{
    plan tests => 9;

    my $pkg = 'Test::Muppet::Command::Update::Friends::Remove';
    ok(UR::Object::Type->get($pkg), 'muppet remove friends command exists'),

    my $cmd = $pkg->create;
    is($cmd->namespace, 'Test::Muppet::Command', 'namespace');
    is($cmd->property_function, 'remove_friend', 'property_function');

    ok(!$cmd->execute, 'fails w/o params');
    $cmd->is_executed(undef);

    $cmd->test_muppets([$test{ernie}]);
    ok(!$cmd->execute, 'fails w/o value');
    $cmd->is_executed(undef);

    is_deeply([sort {$a->name cmp $b->name} $test{ernie}->friends], [sort {$a->name cmp $b->name} ($test{burt}, $test{gonzo})], 'ernie is friends with burt and gonzo');
    $cmd->values([$test{gonzo}]);
    ok($cmd->execute, 'remove friend');
    is_deeply([$test{ernie}->friends], [$test{burt}], 'ernie is friends with burt');
    ok(UR::Context->commit, 'commit');

};

done_testing();
