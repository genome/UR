#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 24;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;

my $c1 = UR::Object::Type->define(class_name => 'URT::Foo', data_source => "URT::DataSource::SomeSQLite", table_name => "FOO");
is($URT::Foo::ISA[0], 'UR::Entity', "defined class has correct inheritance");
is($URT::Foo::Type::ISA[0], 'UR::Entity::Type', "defined class' meta class has correct inheritance");

my $c1b = UR::Object::Type->get(data_source_id => "URT::DataSource::SomeSQLite", table_name => "FOO");
is($c1b,$c1, "defined class is gettable");

my $c2 = UR::Object::Type->create(class_name => 'URT::Bar', data_source => "URT::DataSource::SomeSQLite", table_name => "BAR");
is($URT::Bar::ISA[0], 'UR::Entity', "created class has correct inheritance");
is($URT::Bar::Type::ISA[0], 'UR::Entity::Type', "created class' meta class has correct inheritance");

my $c2b = UR::Object::Type->get(data_source_id => "URT::DataSource::SomeSQLite", table_name => "BAR");
is($c2b,$c2, "created class is gettable");

my $c3_parent = UR::Object::Type->define(
                    class_name => 'URT::BazParent',
                    id_by => ['id_prop_a','id_prop_b'],
                    has => [
                        id_prop_a => { is => 'Integer' },
                        id_prop_b => { is => 'String' },
                        prop_c    => { is => 'Number' },
                    ],
                );
ok($c3_parent, 'Created a parent class');
is($URT::BazParent::ISA[0], 'UR::Object', 'defined class has correct inheritance');
is($URT::BazParent::Type::ISA[0], 'UR::Object::Type', "defined class' meta class has correct inheritance");
my %props = map { $_->property_name => $_ } $c3_parent->properties;
is(scalar(keys %props), 4, 'Parent class property count correct');
is($props{'id_prop_a'}->is_id, '0 but true', 'id_prop_a is an ID property and has the correct rank');
is($props{'id_prop_b'}->is_id, '1', 'id_prop_b is an ID property and has the correct rank');
is($props{'prop_c'}->is_id, undef, 'prop_c is not an ID property');

my %id_props = map { $_->property_name => 1 } $c3_parent->id_properties;
is(scalar(keys %id_props), 3, 'Parent class id property count correct');
is_deeply(\%id_props,
          { id_prop_a => 1, id_prop_b => 1, id => 1 },
          'all ID properties are there');
        
my $c3 = UR::Object::Type->define(
             class_name => 'URT::Baz',
             is => 'URT::BazParent',
             has => [
                 prop_d    => { is => 'Number' },
             ],
          );
ok($c3, 'Created class with some properties and a parent class');
is($URT::Baz::ISA[0], 'URT::BazParent', 'defined class has correct inheritance');
is($URT::Baz::Type::ISA[0], 'URT::BazParent::Type', "defined class' meta class has correct inheritance");
%props = map { $_->property_name => $_ } $c3->properties;
is(scalar(keys %props), 5, 'property count correct');
is($props{'id_prop_a'}->is_id, '0 but true', 'id_prop_a is an ID property and has the correct rank');
is($props{'id_prop_b'}->is_id, '1', 'id_prop_b is an ID property and has the correct rank');
is($props{'prop_c'}->is_id, undef, 'prop_c is not an ID property');
is($props{'prop_d'}->is_id, undef, 'prop_d is not an ID property');


my $other_class = UR::Object::Type->define(
    class_name => 'URT::OtherClass',
    id_by => [
        id => { is => 'String' },
    ],
);
my $parent_with_id_prop = UR::Object::Type->define(
    class_name => 'URT::ParentWithProp',
    has => [
        other_id => { is => 'Integer' },
    ],
);

my $child_without_id_prop = UR::Object::Type->define(
    class_name => 'URT::ChildWithoutProp',
    is => 'URT::ParentWithProp',
    has => [
        other => { is => 'URT::OtherClass', id_by => 'other_id' }
    ],
);
is($child_without_id_prop->property_meta_for_name('other_id')->data_type,
    'Integer',
    'implied property gets data_type from parent when specified');
