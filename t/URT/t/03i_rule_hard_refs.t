#!/usr/bin/env perl

# Test handling of rules and their values with different kinds
# params.

use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;
use Test::More tests => 9;
use Data::Dumper;
use IO::Handle;

class URT::Item {
    id_by => [qw/name group/],
    has => [
        name    => { is => "String" },
        foo     => { is => "String", is_optional => 1 },
        fh      => { is => "IO::Handle", is_optional => 1 },
        scores  => { is => 'ARRAY' },
        things  => { is => 'HASH' },
        relateds => { is => 'URT::Related', reverse_as => 'item', is_many => 1 },
        related_ids => { via => 'relateds', to => 'id', is_many => 1 },
    ]
};

class URT::Related {
    has => {
        item => { is => 'URT::Item', id_by => 'item_id' },
    }
};


my $scores = [1,2,3];
my $things = {'one' => 1, 'two' => 2, 'three' => 3};
my $related_ids = [1,2,3];

my $rule = URT::Item->define_boolexpr(name => 'Bob', scores => $scores, things => $things, related_ids => $related_ids);
ok($rule, 'Created boolexpr');

is($rule->value_for('name'), 'Bob', 'Value for name is correct');
is($rule->value_for('scores'), $scores, 'Getting the value for "scores" returns the exact same array as was put in');
is($rule->value_for('things'), $things, 'Getting the value for "things" returns the exact same hash as was put in');
is($rule->value_for('related_ids'), $related_ids, 'Getting the value for "related_ids" does not return the exact same array as was put in');

my $tmpl = UR::BoolExpr::Template->resolve('URT::Item', 'name','scores','things','related_ids');
ok($tmpl, 'Created BoolExpr template');

my $rule_from_tmpl = $tmpl->get_rule_for_values('Bob', $scores, $things,$related_ids);
#ok($rule_from_tmpl, 'Created BoolExpr from that template');

is($rule_from_tmpl->value_for('scores'), $scores, 'Getting the value for "scores" returns the exact same array as was put in');
is($rule_from_tmpl->value_for('things'), $things, 'Getting the value for "things" returns the exact same hash as was put in');
is($rule_from_tmpl->value_for('related_ids'), $related_ids, 'Getting the value for "related_ids" does not return the exact same array as was put in');

