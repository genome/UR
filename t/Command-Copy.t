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
        target_class => 'Test::Person',
        sub_command_configs => \%sub_command_configs,
    );

    $test{cmd} = 'Test::Person::Command::Copy';
    ok(UR::Object::Type->get($test{cmd}), 'person copy command exists'),

    $test{person} = Test::Person->create(
        name => 'Moe',
        title => 'mr',
        has_pets => 'yes',
    );
    ok($test{person}, 'create test person');
    ok(UR::Context->commit, 'commit');

};

subtest 'fails' => sub{
    plan tests => 4;

    throws_ok(sub{ $test{cmd}->execute(source => $test{person}, changes => [ "= Slow" ]); }, qr/Invalid change/, 'fails w/ invalid change');
    throws_ok(sub{ $test{cmd}->execute(source => $test{person}, changes => [ "names.= Slow" ]); }, qr/Invalid property/, 'fails w/ invalid property');
    throws_ok(sub{ $test{cmd}->execute(source => $test{person}, changes => [ "name.= Slow", "has_pets=dunno" ]); }, qr/Failed to commit/, 'fails w/ invalid has_pets');
    ok(!Test::Person->get(name => 'More Slow'), 'did not create person w/ invalid has_pets;');

};

subtest 'copy' => sub{
    plan tests => 5;

    lives_ok(sub{ $test{cmd}->execute(source => $test{person}, changes => [ "name.= Slow", "has_pets=no" ]); }, 'copy');

    my $new_person = Test::Person->get(name => 'Moe Slow');
    ok($new_person, 'created new person');
    is($new_person->title, 'mr', 'title is the same');
    is($new_person->has_pets, 'no', 'changed has_pets');

    ok(UR::Context->commit, 'commit');

};

done_testing();
