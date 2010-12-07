#!/usr/bin/env perl

# Test handling of rules and their values with different kinds
# params.

use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;
use Test::More tests => 17;
use Data::Dumper;
use IO::Handle;

class URT::RelatedItem {
    id_by => 'ritem_id',
    has => [
        ritem_property => { is => 'String' },
    ],
};

class URT::Item {
    id_by => [qw/name group/],
    has => [
        name    => { is => "String" },
        parent  => { is => "URT::Item", is_optional => 1, id_by => ['parent_name','parent_group'] },
        foo     => { is => "String", is_optional => 1 },
        fh      => { is => "IO::Handle", is_optional => 1 },
        score   => { is => 'Integer' },
        ritem   => { is => 'URT::RelatedItem', id_by => 'ritem_id' },
    ]
};

my($r, @values, $n, $expected,$fh);

$r = URT::Item->define_boolexpr(name => ['Bob'], foo => undef, -hints => ['ritem']);
ok($r, 'Created boolexpr');

# These values are in the same order as the original rule definition
@values = $r->values();
is(scalar(@values), 2, 'Got back 2 values from rule');
$expected = [['Bob'], undef];
is_deeply(\@values, $expected, "Rule's values are correct");

$n = $r->normalize;
ok($n, 'Normalized rule');
# Normalized values come back alpha sorted by their param's name
# foo, name
@values = $n->values();
$expected = [undef, ['Bob']];
is_deeply(\@values, $expected, "Normalized rule's values are correct");



$fh = IO::Handle->new();
$r = URT::Item->define_boolexpr(name => ['Bob'], fh => $fh, foo => undef);

# These values are in the same order as the original rule definition
@values = $r->values();
is(scalar(@values), 3, 'Got back 3 values from rule');
$expected = [['Bob'], $fh, undef];
is_deeply(\@values, $expected, "Rule's values are correct");

$n = $r->normalize;
ok($n, 'Normalized rule');
# Normalized values come back alpha sorted by their param's name
# fh, foo, name
@values = $n->values();
$expected = [$fh, undef, ['Bob']];
is_deeply(\@values, $expected, "Normalized rule's values are correct");





$r = URT::Item->define_boolexpr(name => ['Bob'], fh => $fh, foo => undef, -hints => ['ritem']);

# These values are in the same order as the original rule definition
@values = $r->values();
is(scalar(@values), 3, 'Got back 3 values from rule');
$expected = [['Bob'], $fh, undef];
is_deeply(\@values, $expected, "Rule's values are correct");

$n = $r->normalize;
ok($n, 'Normalized rule');
# Normalized values come back alpha sorted by their param's name
# -hints, fh, foo, name
@values = $n->values();
$expected = [$fh, undef, ['Bob']];
is_deeply(\@values, $expected, "Normalized rule's values are correct");




$r = URT::Item->define_boolexpr(name => [$fh], score => 1, foo => undef, -hints => ['ritem']);
# These values are in the same order as the original rule definition
$DB::stopper=1;
@values = $r->values();
is(scalar(@values), 3, 'Got back 3 values from rule');
$expected = [[$fh], 1, undef];
is_deeply(\@values, $expected, "Rule's values are correct");

$n = $r->normalize;
ok($n, 'Normalized rule');
# Normalized values come back alpha sorted by their param's name
# foo, name, score
@values = $n->values();
$expected = [undef, [$fh], 1];
is_deeply(\@values, $expected, "Normalized rule's values are correct");



