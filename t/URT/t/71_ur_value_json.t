use strict;
use warnings;
use Test::More tests => 8;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;


UR::Object::Type->define(
    is => 'UR::Value::JSON',
    class_name => 'URT::JSONTestValue',
    id_by => ['prop_a','prop_b'],
);

test_create();
test_get_from_properties();

test_get_by_id_single();
test_get_by_id_multiple();

sub test_create {
    my $obj = URT::JSONTestValue->create(prop_a => 'tc_a', prop_b => 'tc_b');
    my $expected_id = '{"prop_a":"tc_a","prop_b":"tc_b"}';
    is( $obj->id,$expected_id, 'id is expected json (create)');
}

sub test_get_from_properties {
    my $obj = URT::JSONTestValue->get(prop_a => 'tgfp_a', prop_b => 'tgfp_b');
    my $expected_id = '{"prop_a":"tgfp_a","prop_b":"tgfp_b"}';
    is($obj->id, $expected_id, 'id is expected json (get)');
}

sub test_get_by_id_single {
    my $obj = URT::JSONTestValue->get('{"prop_a":"gs_a","prop_b":"gs_b"}');
    is($obj->prop_a,'gs_a',  'prop_a matches (single)');
    is($obj->prop_b, 'gs_b', 'prop_b matches (single)');
}

sub test_get_by_id_multiple {
    my @objs = URT::JSONTestValue->get(id => [
        '{"prop_a":"gm1_a","prop_b":"gm1_b"}',
        '{"prop_a":"gm2_a","prop_b":"gm2_b"}',
    ]);
    is($objs[0]->prop_a, 'gm1_a', 'prop_a matches (multiple 1)');
    is($objs[0]->prop_b, 'gm1_b', 'prop_b matches (multiple 1)');
    is($objs[1]->prop_a, 'gm2_a', 'prop_a matches (multiple 2)');
    is($objs[1]->prop_b, 'gm2_b', 'prop_b matches (multiple 2)');
}
