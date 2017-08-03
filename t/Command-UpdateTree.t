#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use TestEnvCrud;

use Test::More tests => 1;

subtest 'tests' => sub{
    plan tests => 4;

    use_ok('Command::UpdateTree') or die;
    use_ok('Command::Crud') or die;

    my %sub_command_configs = map { $_ => { skip => 1 } } grep { $_ ne 'update' } Command::Crud->buildable_sub_command_names;
    Command::Crud->create_command_subclasses(
        target_class => 'Test::Person',
        sub_command_configs => \%sub_command_configs,
    );

    my $cmd = 'Test::Person::Command::Update';
    ok(UR::Object::Type->get($cmd), 'person update tree command exists'),
    isa_ok($cmd, 'Command::UpdateTree');

};

done_testing();
