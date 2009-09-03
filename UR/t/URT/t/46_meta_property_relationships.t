use Test::More;

use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;

plan tests => 21;

# This re-uses classes from testcase 43

&test_relations();

&test_inheritance();

sub test_relations {

    my $p_class = URT::43Primary->get_class_object();
    ok($p_class, 'Loaded URT::43Primary class');

    my $r_class = URT::43Related->get_class_object();
    ok($r_class, 'Loaded URT::43Related class');

    my @props = $p_class->direct_property_metas();
    is(scalar(@props), 5, 'URT::43Primary has 5 properites');
    my @names = sort map { $_->property_name } @props;
    is_deeply(\@names,
              [ qw( primary_id primary_value rel_id related_object related_value ) ],
              'URT::43Primary property names check out');

    my $prop = $p_class->direct_property_meta(property_name => 'related_value');
    ok($prop, 'singular property accessor works');
    is($prop->property_name, 'related_value', 'and it is the right property');

    my $c = $prop->class_meta;
    ok($c, 'class_meta() on a property');
    isa_ok($c, 'UR::Object::Type');
    is($c->class_name, 'URT::43Primary');

    my @ids = $p_class->direct_id_property_metas();
    is(scalar(@ids), 1, 'id_property_metas returned 1 object');
    
    my @refs = $p_class->reference_metas();
    is(scalar(@refs), 1, 'Correctly got 1 reference meta object');
    is($refs[0]->class_meta->id, $p_class->id, 'reference meta points to the right class meta');
    is($refs[0]->r_class_meta->id, $r_class->id, 'reference meta points to the right r_class meta');

    
    my @ref_props = $p_class->reference_property_metas();
    is(scalar(@ref_props), 1, 'Correctly got 1 reference property meta object');
    is($ref_props[0]->class_meta->id, $p_class->id, 'reference property meta points to the right class meta');
    is($ref_props[0]->r_class_meta->id, $r_class->id, 'reference property meta points to the right r_class meta');

    is($ref_props[0]->reference_meta->id, $refs[0]->id, 'reference property meta points to the right reference meta');
    
    my $p = $ref_props[0]->property_meta;
    ok($p, 'reference property meta returned a property_meta');
    is($p->property_name,
       'rel_id',
       'reference property meta points to the right property_meta');

    $p = $ref_props[0]->r_property_meta;
    ok($p, 'reference property meta returned an r_property_meta');
    is($p->property_name,
       'related_id',
       'reference property meta points to the right r_property_meta');

}


sub test_inheritance {

}
