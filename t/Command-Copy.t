#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use TestEnvCrud;

use Test::Exception;
use Test::More tests => 3;

my %test;
subtest 'setup' => sub{
    plan tests => 5;

    use_ok('Command::Copy') or die;
    use_ok('Command::Crud') or die;

    my %sub_command_configs = map { $_ => { skip => 1 } } grep { $_ ne 'copy' } Command::Crud->buildable_sub_command_names;
    Command::Crud->create_command_subclasses(
        target_class => 'Test::Muppet',
        sub_command_configs => \%sub_command_configs,
    );

    $test{cmd} = 'Test::Muppet::Command::Copy';
    ok(UR::Object::Type->get($test{cmd}), 'muppet copy command exists'),

    $test{ernie} = Test::Muppet->create(
        name => 'ernie',
        title => 'mr',
        job => Test::Job->create(name => 'troublemaker'),
    );
    ok($test{ernie}, 'create ernie');
    ok(UR::Context->commit, 'commit');

};

subtest 'fails' => sub{
    plan tests => 4;

    throws_ok(sub{ $test{cmd}->execute(source => $test{ernie}, changes => [ "= Invalid Change" ]); }, qr/Invalid change/, 'fails w/ invalid change');
    throws_ok(sub{ $test{cmd}->execute(source => $test{ernie}, changes => [ "names.= Burt" ]); }, qr/Invalid property/, 'fails w/ invalid property');
    throws_ok(sub{ $test{cmd}->execute(source => $test{ernie}, changes => [ "name.= jr", "title=invalid" ]); }, qr/Failed to commit/, 'fails w/ invalid title');
    ok(!Test::Muppet->get(name => 'ernie jr'), 'did not create muppet w/ invalid title;');

};

subtest 'copy' => sub{
    plan tests => 5;

    lives_ok(sub{ $test{cmd}->execute(source => $test{ernie}, changes => [ "name.= sr", "title=dr" ]); }, 'copy');

    my $new = Test::Muppet->get(name => 'ernie sr');
    ok($new, 'created new muppet');
    is($new->title, 'dr', 'title is dr');
    is($new->job, $test{ernie}->job, 'job is the same');

    ok(UR::Context->commit, 'commit');

};

done_testing();
