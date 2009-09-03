#!/usr/bin/env perl 

use strict;
use warnings;
use UR;
use Test::More tests => 17;

UR::Object::Type->define(
    class_name => 'URT::Parent',
    has => [
        name => { is => 'String', default_value => 'Anonymous' },
    ],
);

UR::Object::Type->define(
    class_name => 'URT::Child',
    is => 'URT::Parent',
    has => [
        color => { is => 'String', default_value => 'clear' },
    ],
);

UR::Object::Type->define(
    class_name => 'URT::SingleChild',
    is => ['UR::Singleton', 'URT::Child'],
);


my $p = URT::Parent->create(id => 1);
ok($p, 'Created a parent object without name');
is($p->name, 'Anonymous', 'object has default value for name');
is($p->name('Bob'), 'Bob', 'We can set the name');
is($p->name, 'Bob', 'And it returns the correct name after setting it');

$p = URT::Parent->create(id => 2, name => 'Fred');
ok($p, 'Created a parent object with a name');
is($p->name, 'Fred', 'Returns the correct name');



my $c = URT::Child->create();
ok($c, 'Created a child object without name or color');
is($c->name, 'Anonymous', 'child has the default value for name');
is($c->color, 'clear', 'child has the default value for color');
is($c->name('Joe'), 'Joe', 'we can set the value for name');
is($c->name, 'Joe', 'And it returns the correct name after setting it');
is($c->color, 'clear', 'color still returns the default value');

$main::printer=1;
$c = URT::SingleChild->_singleton_object;
ok($c, 'Got an object for the child singleton class');
is($c->name, 'Anonymous','name has the default value');
is($c->name('Mike'), 'Mike', 'we can set the name');
is($c->name, 'Mike', 'And it returns the correct name after setting it');
is($c->color, 'clear', 'color still returns the default value');


