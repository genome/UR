use Test::More;

use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;

plan tests => 36;

ok( UR::Object::Type->define(
        class_name => 'URT::Related',
        id_by => [rel_id => { is => 'Integer' }],
        has => [
            related_value => { is => 'String' },
        ],
     ), 'Define related class');


ok( UR::Object::Type->define(
        class_name => 'URT::Parent',
        id_by => [ parent_id => { is => 'Integer' } ],
        has => [
            parent_value => { is => 'String' },
            related_object => { is => 'URT::Related', id_by => 'rel_id' },
            related_value => { via => 'related_object', to => 'related_value' },
        ]
   ), 'Define parent class');

ok( UR::Object::Type->define(
        class_name => 'URT::Child',
        is => 'URT::Parent',
        id_by => [ child_id => { is => 'Integer' } ],
        has =>  [
           child_value => { is => 'String' },
        ],
   ), 'Define child class');


my $parent_meta = URT::Parent->__meta__;
ok($parent_meta, 'Parent class metadata');


my @props = $parent_meta->direct_property_metas();
is(scalar(@props), 5, 'Parent class has 5 direct properties with direct_property_metas');
my @names = sort map { $_->property_name } @props;
my @expected = qw(parent_id parent_value rel_id related_object related_value);
is_deeply(\@names, \@expected, 'Property names check out');
@names = sort $parent_meta->direct_property_names;
is_deeply(\@names, \@expected, 'Property names from direct_property_names are correct');

my $prop = $parent_meta->direct_property_meta(property_name => 'related_value');
ok($prop, 'singular property accessor works');


my $child_meta = URT::Child->__meta__;
ok($child_meta, 'Child class metadata');

@props = $child_meta->direct_property_metas();
is(scalar(@props), 2, 'Child class has 2 direct properties');
@names = sort map { $_->property_name } @props;
@expected = qw(child_id child_value);
is_deeply(\@names, \@expected, 'Property names check out');
@names = sort $child_meta->direct_property_names;
is_deeply(\@names, \@expected, 'Property names from direct_property_names are correct');

@props = $child_meta->all_property_metas();
is(scalar(@props), 8, 'Child class has 8 properties through all_property_metas');
@names = sort map { $_->property_name } @props;
@expected = qw(child_id child_value id parent_id parent_value rel_id related_object related_value),
is_deeply(\@names,\@expected, 'Property names check out');

# properties() only returns properties with storage, not object accessors or the property named 'id'
@props = $child_meta->properties();
is(scalar(@props), 6, 'Child class has 6 properties through properties()');
@names = sort map { $_->property_name } @props;
@expected = qw(child_id child_value parent_id parent_value rel_id related_value),
is_deeply(\@names,\@expected, 'Property names check out');

$prop = $child_meta->direct_property_meta(property_name => 'related_value');
ok(! $prop, "getting a property defined on parent class through child's direct_property_meta finds nothing");
$prop = $child_meta->property_meta_for_name('related_value');
ok($prop, "getting a property defined on parent class through child's property_meta_for_name works");


ok(UR::Object::Property->create( class_name => 'URT::Child', property_name => 'extra_property', data_type => 'String'),
   'Created an extra property on Child class');

@props = $child_meta->properties();
is(scalar(@props), 7, 'Child class now has 7 properties()');
@names = map { $_->property_name } @props;
@expected = qw(child_id child_value extra_property parent_id parent_value rel_id related_value),
is_deeply(\@names, \@expected, 'Property names check out');

@props = $child_meta->direct_property_metas();
is(scalar(@props), 3, 'Child class now has 3 direct_property_metas()');

@props = $child_meta->all_property_metas();
is(scalar(@props), 9, 'Child class now has 9 properties through all_property_names()');
@names = sort map { $_->property_name } @props;
@expected = qw(child_id child_value extra_property id parent_id parent_value rel_id related_object related_value),
is_deeply(\@names, \@expected, 'Property names check out');



ok(UR::Object::Property->create( class_name => 'URT::Parent', property_name => 'parent_extra', data_type => 'String'),
   'Created extra property on parent class');

@props = $parent_meta->direct_property_metas();
is(scalar(@props), 6, 'Parent class now has 6 direct properties with direct_property_metas');
@names = sort map { $_->property_name } @props;
@expected = qw(parent_extra parent_id parent_value rel_id related_object related_value);
is_deeply(\@names, \@expected, 'Property names check out');
@names = sort $parent_meta->direct_property_names;
is_deeply(\@names, \@expected, 'Property names from direct_property_names are correct');

@props = $child_meta->properties();
is(scalar(@props), 8, 'Child class now has 8 properties()');
@names = map { $_->property_name } @props;
@expected = qw(child_id child_value extra_property parent_extra parent_id parent_value rel_id related_value),
is_deeply(\@names, \@expected, 'Property names check out');

@props = $child_meta->all_property_metas();
is(scalar(@props), 10, 'Child class now has 10 properties through all_property_names()');
@names = sort map { $_->property_name } @props;
@expected = qw(child_id child_value extra_property id parent_extra parent_id parent_value rel_id related_object related_value),
is_deeply(\@names, \@expected, 'Property names check out');





my @classes = $child_meta->parent_class_metas();
is(scalar(@classes), 1, 'Child class has 1 parent class');
@names = map { $_->class_name } @classes;
@expected = qw( URT::Parent );
is_deeply(\@names, \@expected, 'parent class names check out');

@names = sort $child_meta->ancestry_class_names;
is(scalar(@names), 2, 'Child class has 2 ancestry classes');
@expected = qw( UR::Object URT::Parent );
is_deeply(\@names, \@expected, 'Class names check out');

