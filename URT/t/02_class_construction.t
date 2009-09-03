#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 6;

use URT;

my $c1 = UR::Object::Type->define(class_name => 'URT::Foo', data_source => "URT::DataSource::SomeSQLite", table_name => "FOO");
is($URT::Foo::ISA[0], 'UR::Entity', "defined class has correct inheritance");
is($URT::Foo::Type::ISA[0], 'UR::Entity::Type', "defined class' meta class has correct inheritance");

my $c1b = UR::Object::Type->get(data_source => "URT::DataSource::SomeSQLite", table_name => "FOO");
is($c1b,$c1, "defined class is gettable");

my $c2 = UR::Object::Type->create(class_name => 'URT::Bar', data_source => "URT::DataSource::SomeSQLite", table_name => "BAR");
is($URT::Bar::ISA[0], 'UR::Entity', "created class has correct inheritance");
is($URT::Bar::Type::ISA[0], 'UR::Entity::Type', "created class' meta class has correct inheritance");

my $c2b = UR::Object::Type->get(data_source => "URT::DataSource::SomeSQLite", table_name => "BAR");
is($c2b,$c2, "created class is gettable");



