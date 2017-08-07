#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use TestEnvCrud;

use Test::Exception;
use Test::More tests => 4;

my %test = ( pkg => 'Command::CrudUtil', );
subtest 'setup' => sub{
    plan tests => 2;

    use_ok($test{pkg}) or die;

    $test{muppet} = Test::Muppet->create(name => 'ernie');
    ok($test{muppet}, 'create muppet');

};

subtest 'display_name_for_value' => sub{
    plan tests => 1;

    is($test{pkg}->display_name_for_value, 'NULL', 'display_name_for_value for undef is NULL');

};

subtest 'display_id_for_value' => sub{
    plan tests => 5;

    is($test{pkg}->display_id_for_value, 'NULL', 'display_id_for_value for undef');
    is($test{pkg}->display_id_for_value(1), 1, 'display_id_for_value for string');
    is($test{pkg}->display_id_for_value($test{muppet}), $test{muppet}->id, 'display_id_for_value for object w/ id');

    throws_ok(sub{ $test{pkg}->display_id_for_value({}); }, qr/Do not pass/, 'fails w/ hash'); 
    throws_ok(sub{ $test{pkg}->display_id_for_value([]); }, qr/Do not pass/, 'fails w/ array'); 

};

subtest 'resolve_incoming_property_names' => sub{
    plan tests => 5;

    throws_ok(sub{$test{pkg}->resolve_incoming_property_names({}); }, qr/Dunno how to/, 'resolve_incoming_property_names fails w/ {}');

    ok(!$test{pkg}->resolve_incoming_property_names, 'resolve_incoming_property_names for nothing');
    is_deeply([$test{pkg}->resolve_incoming_property_names('thing')], [qw/ thing /], 'resolve_incoming_property_names for thing');
    is_deeply([$test{pkg}->resolve_incoming_property_names('thing_id')], [qw/ thing /], 'resolve_incoming_property_names for thing_id');
    is_deeply([$test{pkg}->resolve_incoming_property_names([qw/ thing1 thing2 /])], [qw/ thing1 thing2 /], 'resolve_incoming_property_names for [ thing1 thing2 ]');

};

done_testing();
