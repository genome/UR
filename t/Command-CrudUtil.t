#!/usr/bin/env perl

use strict;
use warnings 'FATAL';

use TestEnv;

use Test::Exception;
use Test::More tests => 4;

my %test = ( pkg => 'Command::CrudUtil', );
subtest 'setup' => sub{
    plan tests => 1;

    use_ok($test{pkg}) or die;

};

subtest 'camel_case_to_string' => sub{
    plan tests => 3;

    throws_ok(sub{ $test{pkg}->camel_case_to_string; }, qr/2 were expected/, 'camel_case_to_string fails w/o string');
    is($test{pkg}->camel_case_to_string('Thing'), 'thing', 'camel_case_to_string Thing => thing');
    is($test{pkg}->camel_case_to_string('GreatThing'), 'great thing', 'camel_case_to_string GreatThing => great thing');
};

subtest 'display_name_for_value' => sub{
    plan tests => 1;

    is($test{pkg}->display_name_for_value, 'NULL', 'display_name_for_value for undef is NULL');

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
