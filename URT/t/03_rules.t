#!/usr/bin/env perl

use strict;
use warnings;
use URT;
use Test::More tests => 22;
use Data::Dumper;

class URT::Item {
    id_by => [qw/name group/],
    has => [
        name    => { is => "String" },
        group   => { is => "String" },
        parent  => { is => "URT::Item", is_optional => 1, id_by => ['parent_name','parent_group'] },
        foo     => { is => "String", is_optional => 1 },
        bar     => { is => "String", is_optional => 1 },
    ]
};

class URT::FancyItem {
    is  => 'URT::Item',
    has => [
        feet    => { is => "String" }
    ]
};


my $m = URT::FancyItem->get_class_object;
ok($m, "got metadata for test class");

my @p = $m->id_property_names;
is("@p", "name group", "property names are correct");

my $p = URT::FancyItem->create();
ok($p, "made a parent object");

my $c = URT::FancyItem->create(parent => $p);
ok($c, "made a child object which references it");

my $r = URT::FancyItem->get_rule_for_params(foo => 222, -recurse => [qw/parent_name name parent_group group/], bar => 555);
ok($r, "got a rule to get objects using -recurse");

is($r->value_position_for_property_name('foo'),0, "position is as expected for variable param 1");
is($r->value_position_for_property_name('bar'),1, "position is as expected for variable param 2");
is($r->value_position_for_property_name('-recurse'),0, "position is as expected for constant param 1");

is_deeply(
    [$r->params_list],
    [foo => 222, -recurse => [qw/parent_name name parent_group group/], bar => 555],
    "params list for the rule is as expected"
)
    or print Dumper([$r->params_list]);
    
my $t = $r->get_rule_template;
ok($t, "got a template for the rule");

is($t->value_position_for_property_name('foo'),0, "position is as expected for variable param 1");
is($t->value_position_for_property_name('bar'),1, "position is as expected for variable param 2");
is($t->value_position_for_property_name('-recurse'),0, "position is as expected for constant param 1");

my @names = $t->_property_names;
is("@names","foo bar", "rule template knows its property names");

my $r2 = $t->get_rule_for_values(333,666);
ok($r2, "got a new rule from the template with different values for the non-constant values");

is_deeply(
    [$r2->params_list],
    [foo => 333, -recurse => [qw/parent_name name parent_group group/], bar => 666],
    "the new rule has the expected structure"
)
    or print Dumper([$r->params_list]);

$r = URT::FancyItem->get_rule_for_params(foo => { operator => "between", value => [10,30] }, bar => { operator => "like", value => 'x%y' });
$t = $r->get_rule_template();
is($t->operator_for_property_name('foo'),'between', "operator for param 1 is correct");
is($t->operator_for_property_name('bar'),'like', "operator for param 2 is correct");

$r = URT::FancyItem->get_rule_for_params(foo => 10, bar => { operator => "like", value => 'x%y' });
$t = $r->get_rule_template();
is($t->operator_for_property_name('foo'),'', "operator for param 1 is correct");
is($t->operator_for_property_name('bar'),'like', "operator for param 2 is correct");

$r = URT::FancyItem->get_rule_for_params(foo => { operator => "between", value => [10,30] }, bar => 20);
$t = $r->get_rule_template();
is($t->operator_for_property_name('foo'),'between', "operator for param 1 is correct");
is($t->operator_for_property_name('bar'),'', "operator for param 2 is correct");



