#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use TestEnvCrud;

use Test::Exception;
use Test::More tests => 4;

my %test;
subtest 'setup' => sub{
    plan tests => 1;

    %test = (
        pkg => 'Command::Crud',
        target_class => 'Test::Person',
        namespace => 'Test::Person::Command',
        target_name => 'test person',
        target_name_pl => 'test persons',
        target_name_ub => 'test_person',
        target_name_ub_pl => 'test_persons',
        sub_command_names => [qw/ copy create delete list update /],
    );
    use_ok($test{pkg}) or die;

};

subtest 'create_command_subclasses' => sub{
    plan tests => 8;

    throws_ok(sub{ Command::Crud->create_command_subclasses; }, qr/No target_class given/, 'fails w/o target_class');

    my %sub_command_configs = map { $_ => { skip => 1 } } @{$test{sub_command_names}};
    lives_ok(sub{
            $test{crud} = Command::Crud->create_command_subclasses(
                target_class => $test{target_class},
                sub_command_configs => \%sub_command_configs,
                );},
           'create_command_subclasses');
    for ( @{$test{sub_command_names}} ) {
        ok(!UR::Object::Type->get($test{namespace}.'::'.ucfirst($_)), "did not create sub command for $_");
    }
    $test{crud}->delete;

    lives_ok(sub{ $test{crud} = Command::Crud->create_command_subclasses(target_class => $test{target_class}); }, 'create_command_subclasses');

};

subtest 'target names' => sub{
    plan tests => 5;

    my $crud = $test{crud};
    is($crud->namespace, $test{namespace}, 'namespace');
    is($crud->target_name, $test{target_name}, 'target_name');
    is($crud->target_name_pl, $test{target_name_pl}, 'target_name_pl');
    is($crud->target_name_ub, $test{target_name_ub}, 'target_name_ub');
    is($crud->target_name_ub_pl, $test{target_name_ub_pl}, 'target_name_ub_pl');

};

subtest 'commands' => sub{
    plan tests => 12;

    for ( @{$test{sub_command_names}} ) {
        my $method = $_.'_command_class_name';
        my $class_name = $test{crud}->$method;
        is($class_name, $test{namespace}.'::'.ucfirst($_), "$_ subcommand class name");
        lives_ok(sub { $class_name->__meta__; }, "$_ comand was created"); # will unit test individual commands
    }

    is_deeply([sort $test{crud}->namespace_sub_command_names], [sort @{$test{sub_command_names}}], 'namespace_sub_command_names');
    my @namespace_sub_command_classes = map { my $m = $_.'_command_class_name'; $test{crud}->$m($_); } @{$test{sub_command_names}};
    is_deeply([sort $test{crud}->namespace_sub_command_classes], [sort @namespace_sub_command_classes], 'namespace_sub_command_classes');

};

done_testing();
