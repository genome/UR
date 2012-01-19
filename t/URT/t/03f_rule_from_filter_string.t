#!/usr/bin/env perl

# Test the RecDescent parser used by the Lister commands

use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;
use Test::More tests => 500;
use Data::Dumper;
use IO::Handle;

class URT::RelatedItem {
    id_by => 'ritem_id',
    has => [
        ritem_property => { is => 'String' },
        ritem_number   => { is => 'Number' },
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

foreach my $test (
    { string => 'name = bob',
      values => { name => 'bob' },
      operators => { name => '=' },
    },
    { string => 'name=bob',
      values => { name => 'bob' },
      operators => { name => '=' },
    },
    { string => 'name=>bob',
      values => { name => 'bob' },
      operators => { name => '=' },
    },
    { string => 'name=a-longer-string',
      values => { name => 'a-longer-string' },
      operators => { name => '=' },
    },
    { string => 'name=2012-jan-12',
      values => { name => '2012-jan-12' },
      operators => { name => '=' },
      #stop => 1,
    },
    { string => 'name=fred and score>2',
      values => { name => 'fred', score => 2 },
      operators => { name => '=', score => '>'},
    },
    { string => 'name=",",score=2',
      values => { name => ',', score => 2 },
      operators => { name => '=', score => '=' },
    },
    { string => 'name=and and score=2' ,
      values => { name => 'and', score => 2 },
      operators => { name => '=', score => '=' },
    },
    { string => 'name in [bob,fred] and score<-2',
      values => { name => ['bob','fred'], score => -2 },
      operators => { name => 'in', score => '<' }
    },
    { string => 'score = -12.2' ,
      values => { score => -12.2 },
      operators => { score => '=' },
    },
    { string => 'score = .2' ,
      values => { score => .2 },
      operators => { score => '=' },
    },
    { string => 'score = -.2' ,
      values => { score => -0.2 },
      operators => { score => '=' },
    },
    { string => 'name=fred and score>2,foo=bar',
      values => { name => 'fred', score => 2, foo => 'bar' },
      operators => { name => '=', score => '>', foo => '='}
    },
    { string => 'score!:-100--10.2',
      values => { score => [-100, -10.2] },
      operators => { score => 'not between' },
#stop => 1,
    },
    { string => 'name~%yoyo,score:10-100',
      values => { name => '%yoyo', score => [10,100] },
      operators => { name => 'like', score => 'between' }
    },
    { string => 'name like yoyo',
      values => { name => '%yoyo%' },
      operators => { name => 'like' }
    },
    { string => 'foo:one/two/three',
      values => { foo => ['one','three','two'] },  # They get sorted internally
      operators => { foo => 'in' },
    },
    { string => 'foo!:one/two/three',
      values => { foo => ['one','three','two'] },  # They get sorted internally
      operators => { foo => 'not in' },
    },
    { string => 'name=/a/path/name',
      values => { name => '/a/path/name' },
      operators => { name => '=' },
    },
    { string => 'name:a/path/name',
      values => { name => ['a','name','path'] },
      operators => { name => 'in' },
    },
    { string => 'name in ["/a/path/name","/other/path/","relative/path/name"]',
      values => { name => ['/a/path/name','/other/path/','relative/path/name'] },
      operators => {name => 'in' },
    },
    { string => 'score in [1,2,3]',
      values => { score => [1,2,3] },
      operators => { score => 'in' },
    },
    { string => 'score not in [1,2,3]',
      values => { score => [1,2,3] },
      operators => { score => 'not in' },
    },
    { string => 'foo:one/two/three,score:10-100',  # These both use :
      values => { foo => ['one','three','two'], score => [10,100] },
      operators => { foo => 'in', score => 'between' },
    },
    { string => 'foo!:one/two/three,score:10-100',  # These both use :
      values => { foo => ['one','three','two'], score => [10,100] },
      operators => { foo => 'not in', score => 'between' },
    },
    { string => q(name="bob is cool",foo:'one "two"'/three),
      values => { name => 'bob is cool', foo => ['one "two"','three'] },
      operators => { name => '=', foo => 'in' },
    },
    { string => 'name not like %joe',
      values => { name => '%joe' },
      operators => { name => 'not like' },
    },
    { string => 'name ! like %joe',
      values => { name => '%joe' },
      operators => { name => 'not like' },
    },
    { string => 'name !~%joe',
      values => { name => '%joe' },
      operators => { name => 'not like' },
    },
    { string => 'name not like %joe and score!:10-100 and foo!:one/two/three',
      values => { name => '%joe', score => [10,100], foo => ['one', 'three', 'two'] },
      operators => { name => 'not like', score => 'not between', foo => 'not in' }
    },
    { string => 'name=foo and ritem.ritem_property=bar',
      values => { name => 'foo', 'ritem.ritem_property' => 'bar' },
      operators => { name => '=', 'ritem.ritem_property' => '=' },
    },
    { string => 'name=foo,ritem.ritem_property=bar,ritem.ritem_number=.2',
      values => { name => 'foo', 'ritem.ritem_property' => 'bar','ritem.ritem_number' => 0.2 },
      operators => { name => '=', 'ritem.ritem_property' => '=', 'ritem.ritem_number' => '=' },
    },
    { string => 'name=foo and foo=bar and score=2',
      values => { name => 'foo', foo => 'bar', score => 2 },
      operators => { name => '=', foo => '=', score => '=' },
    },
    { string => 'name=foo and ( foo=bar and score=2 )',
      values => { name => 'foo', foo => 'bar', score => 2 },
      operators => { name => '=', foo => '=', score => '=' },
    },
    { string => 'name=foo order by score' ,
      values => { name => 'foo' },
      operators => { name => '=' },
      order_by => ['score'],
    },
    { string => 'name=foo order by -score' ,
      values => { name => 'foo' },
      operators => { name => '=' },
      order_by => ['-score'],
    },
    { string => 'name=foo order by score,foo',
      values => { name => 'foo' },
      operators => { name => '=' },
      order_by => ['score','foo'],
    },
    { string => 'name=foo order by score,-foo',
      values => { name => 'foo' },
      operators => { name => '=' },
      order_by => ['score','-foo'],
    },
    { string => 'name=foo order by -score,-foo',
      values => { name => 'foo' },
      operators => { name => '=' },
      order_by => ['-score','-foo'],
    },
    { string => 'name=foo order by -score,-foo',
      values => { name => 'foo' },
      operators => { name => '=' },
      order_by => ['-score','-foo'],
    },
    { string => 'name=foo order by -score,-foo group by ritem_id',
      values => { name => 'foo' },
      operators => { name => '=' },
      order_by => ['-score','-foo'],
      group_by => ['ritem_id'],
    },
    { string => 'name=foo order by -score,-foo group by ritem_id, parent_name',
      values => { name => 'foo' },
      operators => { name => '=' },
      order_by => ['-score','-foo'],
      group_by => ['ritem_id','parent_name'],
    },
    { string => '',
      values => {},
      operators => {},
    },
    { string => 'order by score',
      values => {},
      operators => {},
      order_by => ['score'],
    },
) {

    my $string = $test->{'string'};
    my $values = $test->{'values'};
    my $value_count = scalar(values %$values);
    my @properties = keys %$values;
    my $operators = $test->{'operators'};

    my $r = UR::BoolExpr->resolve_for_string(
               'URT::Item',
               $test->{'string'});
    ok($r, "Created rule from string \"$string\"");
    my @got_values = $r->values();
    is(scalar(@got_values), $value_count, 'Rule has the right number of values');

    foreach my $property (@properties) {
        is_deeply($r->value_for($property), $values->{$property}, "Value for $property is correct");
        is($r->operator_for($property), $operators->{$property}, "Operator for $property is correct");
    }

    foreach my $meta ( 'order_by', 'group_by' ) {
        if ($test->{$meta}) {
            my $got = $r->template->$meta;
            is_deeply($got, $test->{$meta}, "$meta is correct");
        }
    }
   exit if ($test->{'stop'});
#    print Data::Dumper::Dumper($r);
}
#exit;

# or-type rules need to be checked differently
foreach my $test (
    { string => 'name=bob or foo=bar',
      rules => [
                 { values => { name => 'bob' },
                   operators => { name => '=' },
                 },
                 { values => { foo => 'bar' },
                   operators => { foo => '=' },
                 }
               ],
    },
    { string => 'name=bob and score=2 or name =fred and foo=bar',
      rules => [
                   { values => { name => 'bob', score => 2 },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => 'fred', foo => 'bar' },
                     operators => { name => '=', foo => '=' },
                   }
               ],
    },
    { string => 'name=bob or name=foo or foo=bar',
      rules => [
                  { values => { name => 'bob' },
                    operators => { name => '=' },
                  },
                  { values => { name => 'foo' },
                    operators => { name => '=' },
                  },
                  { values => { foo => 'bar' },
                    operators => { foo => '=' },
                  },
               ],
    },
    { string => 'name=bob and (score=2 or foo=bar)',
      rules => [
                   { values => { name => 'bob', score => 2, },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => 'bob', foo => 'bar' },
                     operators => { name => '=', foo => '=' },
                   },
               ],
    },
    { string => '(name=bob or name=joe) and (score = 2 or score = 4)',
      rules => [
                   { values => { name => 'bob', score => 2 },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => 'bob', score => 4 },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => 'joe', score => 2 },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => 'joe', score => 4 },
                     operators => { name => '=', score => '=' },
                   },
                ],
    },
    { string => 'name = bob and (score=2 or foo=bar and (name in ["bob","fred","joe"] and score > -10.16))',
      rules => [
                   { values => { name => 'bob', score => 2 },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => ['bob','fred','joe'], foo => 'bar', score => -10.16 },
                     operators => { name => 'in', foo => '=', score => '>' },
                     # calling values() will return 4 things (since name is in there twice), but value_for('name') returns the list
                     override_value_count => 4,
                   },
                ],
    },
    { string => q(name=bob and (score = 2 or (foo:"bar "/baz/' quux "quux" ' and (score!:-100.321--.123 or score<4321)))),
      rules => [
                   { values => { name => 'bob', score => 2 },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => 'bob', foo => [' quux "quux" ', 'bar ','baz'], score => [-100.321, -0.123]},
                     operators => { name => '=', foo => 'in', score => 'not between' },
                   },
                   { values => { name => 'bob', foo => [' quux "quux" ', 'bar ','baz'], score => 4321 },
                     operators => { name => '=', foo => 'in', score => '<' },
                   },
               ],
    },
    { string => 'name = bob and (score=2 or foo=bar and (name in ["bob","fred","joe"] and score > -10.16))',
      rules => [
                   { values => { name => 'bob', score => 2 },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => ['bob','fred','joe'], foo => 'bar', score => -10.16 },
                     operators => { name => 'in', foo => '=', score => '>' },
                     # calling values() will return 4 things (since name is in there twice), but value_for('name') returns the list
                     override_value_count => 4,
                   },
                ],
    },
    { string => q(name=bob and (score = 2 or (foo:"bar "/baz/' quux "quux" ' and (score!:-100.321--.123 or score<4321)))),
      rules => [
                   { values => { name => 'bob', score => 2 },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => 'bob', foo => [' quux "quux" ', 'bar ','baz'], score => [-100.321, -0.123]},
                     operators => { name => '=', foo => 'in', score => 'not between' },
                   },
                   { values => { name => 'bob', foo => [' quux "quux" ', 'bar ','baz'], score => 4321 },
                     operators => { name => '=', foo => 'in', score => '<' },
                   },
               ],
    },
    { string => 'name = bob and (score=2 or foo=bar and (name in ["bob","fred","joe"] and score > -10.16))',
      rules => [
                   { values => { name => 'bob', score => 2 },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => ['bob','fred','joe'], foo => 'bar', score => -10.16 },
                     operators => { name => 'in', foo => '=', score => '>' },
                     # calling values() will return 4 things (since name is in there twice), but value_for('name') returns the list
                     override_value_count => 4,
                   },
                ],
    },
    { string => q(name=bob and (score = 2 or (foo:"bar "/baz/' quux "quux" ' and (score!:-100.321--.123 or score<4321)))),
      rules => [
                   { values => { name => 'bob', score => 2 },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => 'bob', foo => [' quux "quux" ', 'bar ','baz'], score => [-100.321, -0.123]},
                     operators => { name => '=', foo => 'in', score => 'not between' },
                   },
                   { values => { name => 'bob', foo => [' quux "quux" ', 'bar ','baz'], score => 4321 },
                     operators => { name => '=', foo => 'in', score => '<' },
                   },
               ],
    },
    { string => 'name = bob and (score=2 or foo=bar and (name in ["bob","fred","joe"] and score > -10.16))',
      rules => [
                   { values => { name => 'bob', score => 2 },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => ['bob','fred','joe'], foo => 'bar', score => -10.16 },
                     operators => { name => 'in', foo => '=', score => '>' },
                     # calling values() will return 4 things (since name is in there twice), but value_for('name') returns the list
                     override_value_count => 4,
                   },
                ],
    },
    { string => q(name=bob and (score = 2 or (foo:"bar "/baz/' quux "quux" ' and (score!:-100.321--.123 or score<4321)))),
      rules => [
                   { values => { name => 'bob', score => 2 },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => 'bob', foo => [' quux "quux" ', 'bar ','baz'], score => [-100.321, -0.123]},
                     operators => { name => '=', foo => 'in', score => 'not between' },
                   },
                   { values => { name => 'bob', foo => [' quux "quux" ', 'bar ','baz'], score => 4321 },
                     operators => { name => '=', foo => 'in', score => '<' },
                   },
               ],
    },
    { string => q( name=bob and (score = 2 or ( foo = bar and (parent_name=joe or ((group=cool or ritem.ritem_number<0.123) and (ritem_id = 123 or ritem.ritem_property=mojo)))))),
      rules => [
                   { values => { name => 'bob', score => 2 },
                     operators => { name => '=', score => '=' },
                   },
                   { values => { name => 'bob', foo => 'bar', parent_name => 'joe' },
                     operators => { name => '=', foo => '=', parent_name => '=' },
                   },
                   { values => { name => 'bob', foo => 'bar', group => 'cool', ritem_id => 123 },
                     operators => { name => '=', foo => '=', group => '=', ritem_id => '=' },
                   },
                   { values => { name => 'bob', foo => 'bar', group => 'cool', 'ritem.ritem_property' => 'mojo' },
                     operators => { name => '=', foo => '=', group => '=', 'ritem.ritem_property' => '=' },
                   },
                   { values => { name => 'bob', foo => 'bar', 'ritem.ritem_number' => 0.123, ritem_id => 123 },
                     operators => { name => '=', foo => '=', 'ritem.ritem_number' => '<', ritem_id => '=' },
                   },
                   { values => { name => 'bob', foo => 'bar', 'ritem.ritem_number' => 0.123, 'ritem.ritem_property' => 'mojo' },
                     operators => { name => '=', foo => '=', 'ritem.ritem_number' => '<', 'ritem.ritem_property' => '=' },
                   },
               ],
    },

) {
   $DB::single=1 if ($test->{'stop'});
    my $string = $test->{'string'};
    my $composite_rule = UR::BoolExpr->resolve_for_string('URT::Item',$string);
    ok($composite_rule, "Created rule from string \"$string\"");
    isa_ok($composite_rule->template, 'UR::BoolExpr::Template::Or');

#print Data::Dumper::Dumper($composite_rule);
    my @r = $composite_rule->underlying_rules();
    is(scalar(@r), scalar(@{$test->{'rules'}}), 'Underlying rules count is correct');

    for (my $i = 0; $i< @{ $test->{'rules'}}; $i++) {
        my $r = $r[$i];
        my $test_rule = $test->{'rules'}->[$i];

        my $values = $test_rule->{'values'};
        my $value_count = $test_rule->{'override_value_count'} || scalar(values %$values);
        my @properties = keys %$values;
        my $operators = $test_rule->{'operators'};

        my @got_values = $r->values();
        is(scalar(@got_values), $value_count, "Composite rule $i has the right number of values");

        foreach my $property (@properties) {
            is_deeply($r->value_for($property), $values->{$property}, "Value for $property is correct");
            is($r->operator_for($property), $operators->{$property}, "Operator for $property is correct");
        }
    }
    exit if ($test->{'stop'});
}

foreach my $test (
    { string => 'name in bob/fred and score<-2',
      exception => qr{Syntax error near token 'WORD'.*Expected one of: LEFT_BRACKET}s,
    },
    { string => 'name:[bob,fred] and score<-2',
      exception => qr{Syntax error near token 'LEFT_BRACKET'},
    },
    { string => 'name:/a/path/name',
      exception => qr{Syntax error near token 'IN_DIVIDER'},
    },
    { string => 'score=[1,2,3]',
      exception => qr{Syntax error near token 'LEFT_BRACKET'},
    },
    { string => 'score!=[1,2,3]',
      exception => qr{Syntax error near token 'LEFT_BRACKET'},
    },
) {

    my $string = $test->{'string'};
    my $exception_re = $test->{'exception'};

    my $r;
    eval {
        $r = UR::BoolExpr->resolve_for_string(
               'URT::Item',
               $test->{'string'});
    };
    ok(!$r, "Correctly did not create rule from string \"$string\"");

    like($@, $exception_re, 'exception looks right');
}

1;
                                          


