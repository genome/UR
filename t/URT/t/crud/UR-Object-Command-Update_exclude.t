#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use Path::Class 'file';
use lib file(__FILE__)->dir->parent->parent->parent->parent->subdir("lib")->absolute->stringify;
use lib file(__FILE__)->dir->absolute->stringify;

use TestEnvCrud;
use Test::More tests => 1;

subtest 'exclude properties' => sub{
    plan tests => 7;

    use_ok('UR::Object::Command::Update') or die;
    use_ok('UR::Object::Command::Crud') or die;

    my %sub_command_configs = map { $_ => { skip => 1 } } grep { $_ ne 'update' } UR::Object::Command::Crud->buildable_sub_command_names;
    $sub_command_configs{update}->{exclude} = [qw/ name friends /];
    UR::Object::Command::Crud->create_command_subclasses(
        target_class => 'Test::Muppet',
        sub_command_configs => \%sub_command_configs,
    );

    my $update_job_class_name = 'Test::Muppet::Command::Update::Job';
    ok(UR::Object::Type->get($update_job_class_name), 'update job command exists');

    my $update_name_class_name = 'Test::Muppet::Command::Update::Name';
    ok(!UR::Object::Type->get($update_name_class_name), 'update name command does not exist');

    my $update_name_class_name = 'Test::Muppet::Command::Update::Friends';
    ok(!UR::Object::Type->get($update_name_class_name), 'update friends tree does not exist');
    my $update_name_class_name = 'Test::Muppet::Command::Update::Friends::Add';
    ok(!UR::Object::Type->get($update_name_class_name), 'update add friends command does not exist');
    my $update_name_class_name = 'Test::Muppet::Command::Update::Friends::Remove';
    ok(!UR::Object::Type->get($update_name_class_name), 'update remove friends command does not exist');

};

done_testing();
