#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;
use Test::More tests => 24;

class URT::Item {
    id_by => [qw/name group/],
    has => [
        name    => { is => "String" },
        group   => { is => "String" },
        parent  => { is => "URT::Item", is_optional => 1, id_by => ['parent_name','parent_group'] },
        foo     => { is => "String", is_optional => 1 },
        bar     => { is => "String", is_optional => 1 },
        score   => { is => 'Integer' },
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


my($r1, $r2);


$r1 = URT::FancyItem->define_boolexpr();
ok($r1->is_subset_of($r1), 'boolexpr with no filters is a subset of itself');


$r1 = URT::FancyItem->define_boolexpr(name => 'Bob');
ok($r1->is_subset_of($r1), 'boolexpr with one filter is a subset of itself');


$r1 = URT::Item->define_boolexpr(name => 'Bob');
$r2 = URT::Item->define_boolexpr(name => 'Bob');
ok($r1->is_subset_of($r2), 'Two rules with the same filters are a subset');
ok($r2->is_subset_of($r1), 'Two rules with the same filters are a subset');


$r1 = URT::Item->define_boolexpr(name => 'Bob', group => 'home');
$r2 = URT::Item->define_boolexpr(name => 'Bob', group => 'home');
ok($r1->is_subset_of($r2), 'Two rules with the same filters are a subset');
ok($r2->is_subset_of($r1), 'Two rules with the same filters are a subset');


$r1 = URT::Item->define_boolexpr(name => 'Bob', group => 'home');
$r2 = URT::Item->define_boolexpr(group => 'home', name => 'Bob');
ok($r1->is_subset_of($r2), 'Two rules with the same filters in a different order are a subset');
ok($r2->is_subset_of($r1), 'Two rules with the same filters in a different order are a subset');


$r1 = URT::Item->define_boolexpr(name => 'Bob');
$r2 = URT::Item->define_boolexpr(name => 'Fred');
ok(! $r1->is_subset_of($r2), 'Rule with different value for same filter name is not a subset');
ok(! $r2->is_subset_of($r1), 'Rule with different value for same filter name is not a subset');


$r1 = URT::Item->define_boolexpr(name => 'Bob');
$r2 = URT::Item->define_boolexpr(group => 'Bob');
ok(! $r1->is_subset_of($r2), 'Rule with different param names and same value is not a subset');
ok(! $r2->is_subset_of($r1), 'Rule with different param names and same value is not a subset');


$r1 = URT::Item->define_boolexpr(name => 'Bob');
$r2 = URT::Item->define_boolexpr();
ok($r1->is_subset_of($r2), 'one filter is a subset of no filters');
ok(! $r2->is_subset_of($r1), 'converse is not a subset');


$r1 = URT::Item->define_boolexpr(name => 'Bob', group => 'home');
$r2 = URT::Item->define_boolexpr(name => 'Bob');
ok($r1->is_subset_of($r2), 'Rule with two filters is subset of rule with one filter');
ok(! $r2->is_subset_of($r1),' Rule with one filter is not a subset of rule with two filters');


$r1 = URT::FancyItem->define_boolexpr();
$r2 = URT::Item->define_boolexpr();
ok($r1->is_subset_of($r2), 'subset by inheritance with no filters');
ok(! $r2->is_subset_of($r1), 'ancestry is not a subset');


$r1 = URT::FancyItem->define_boolexpr(name => 'Bob');
$r2 = URT::Item->define_boolexpr(name => 'Bob');
ok($r1->is_subset_of($r2), 'inheritance and one filter is subset');
ok(! $r2->is_subset_of($r1), 'ancestry and one filter is not a subset');


$r1 = URT::FancyItem->define_boolexpr(name => 'Bob', group => 'home');
$r2 = URT::Item->define_boolexpr(group => 'home', name => 'Bob');
ok($r1->is_subset_of($r2), 'inheritance and two filters in different order is subset');
ok(! $r2->is_subset_of($r1), 'ancestry and two filters in different order is not a subset');


$r1 = URT::Item->define_boolexpr(name => 'Bob');
$r2 = URT::UnrelatedItem->define_boolexpr(name => 'Bob');
ok(! $r1->is_subset_of($r2), 'Rules on unrelated classes with same filters is not a subset');
ok(! $r2->is_subset_of($r1), 'Rules on unrelated classes with same filters is not a subset');


