#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;
use Test::More tests => 29;
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

class URT::UnrelatedItem {
    has => [
        name    => { is => "String" },
        group   => { is => "String" },
    ],
};


my $m = URT::FancyItem->__meta__;
ok($m, "got metadata for test class");

my @p = $m->id_property_names;
is("@p", "name group", "property names are correct");

my $b = URT::Item->create(name => 'Joe', group => 'shirts');
ok($b, 'made a base class object');

my $p = URT::FancyItem->create(name => 'Bob', group => 'shirts');
ok($p, "made a parent object");

my $c = URT::FancyItem->create(parent => $p, name => 'Fred', group => 'skins');
ok($c, "made a child object which references it");

my $u = URT::UnrelatedItem->create(name => 'Bob', group => 'shirts');
ok($u, 'made an unrelated item object');

my $r = URT::FancyItem->define_boolexpr(foo => 222, -recurse => [qw/parent_name name parent_group group/], bar => 555);
ok($r, "got a rule to get objects using -recurse");

is($r->template->value_position_for_property_name('foo'),0, "position is as expected for variable param 1");
is($r->template->value_position_for_property_name('bar'),1, "position is as expected for variable param 2");
is($r->template->value_position_for_property_name('-recurse'),0, "position is as expected for constant param 1");

is_deeply(
    [$r->params_list],
    [foo => 222, -recurse => [qw/parent_name name parent_group group/], bar => 555],
    "params list for the rule is as expected"
)
    or print Dumper([$r->params_list]);
    
my $t = $r->template;
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

$r = URT::FancyItem->define_boolexpr(foo => { operator => "between", value => [10,30] }, bar => { operator => "like", value => 'x%y' });
$t = $r->template();
is($t->operator_for('foo'),'between', "operator for param 1 is correct");
is($t->operator_for('bar'),'like', "operator for param 2 is correct");

$r = URT::FancyItem->define_boolexpr(foo => 10, bar => { operator => "like", value => 'x%y' });
$t = $r->template();
is($t->operator_for('foo'),'=', "operator for param 1 is correct");
is($t->operator_for('bar'),'like', "operator for param 2 is correct");

$r = URT::FancyItem->define_boolexpr(foo => { operator => "between", value => [10,30] }, bar => 20);
$t = $r->template();
is($t->operator_for('foo'),'between', "operator for param 1 is correct");
is($t->operator_for('bar'),'=', "operator for param 2 is correct");


# Make a rule on the parent class
$r = URT::Item->define_boolexpr(name => 'Bob', group => 'shirts');
ok($r->evaluate($p), 'Original parent object evaluated though rule');

ok(! $r->evaluate($c), 'Child object with different params evaluated through parent rule returns false');

$r = URT::Item->define_boolexpr(name => 'Fred', group => 'skins');
ok($r->evaluate($c), 'Child object with same params evaluated through parent rule returns true');

# Make a rule on the child class
$r = URT::FancyItem->define_boolexpr(name => 'Joe', group => 'shirts');
ok(! $r->evaluate($b), 'Base class object evaluated through rule on child class returns false');

# An item of a different class but with the same params 
$r = URT::UnrelatedItem->define_boolexpr(name => 'Bob', group => 'shirts');
ok(! $r->evaluate($p), 'Original parent object evaluated false through rule on unrelatd class');



