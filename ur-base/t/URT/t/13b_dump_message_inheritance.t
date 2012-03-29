use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use UR;

use Test::More;

plan tests => 30;

ok(UR::Object::Type->define( class_name => 'A'), 'Define class A');
ok(UR::Object::Type->define( class_name => 'B'), 'Define class B');

my $a = A->create(id => 1);
ok($a, 'Create object a');

my $b = B->create(id => 1);
ok($b, 'Create object b');

# Make sure each instance can control its own messaging flags
is($a->dump_status_messages(0), 0, 'Set dump_status_messages on a to 0');
is($a->dump_status_messages(), 0, 'dump_status_messages on a is still 0');

is($b->dump_status_messages(1), 1, 'Set dump_status_messages on b to 1');
is($b->dump_status_messages(), 1, 'dump_status_messages on b is still 1');

is($a->dump_status_messages(), 0, 'dump_status_messages on a is still 0');
is($b->dump_status_messages(), 1, 'dump_status_messages on b is still 1');

# Make sure classes inherit their messaging behavior from parents if they don't
# otherwise change it
ok(UR::Object::Type->define( class_name => 'Parent'), 'Define class Parent');
ok(UR::Object::Type->define( class_name => 'ChildA', is => 'Parent'), 'Define class ChildA');
ok(UR::Object::Type->define( class_name => 'ChildB', is => 'Parent'), 'Define class ChildB');

$a = ChildA->create();
ok($a, 'Create object a');
$b = ChildB->create();
ok($b, 'Create object b');

is(Parent->dump_status_messages(), undef, 'Parent dump_status_messages() starts off as undef');
is(Parent->dump_status_messages(0), 0, 'Setting Parent dump_status_messages() to 0');
is(ChildA->dump_status_messages(), 0, 'ChildA dump_status_messages() is 0');
is($a->dump_status_messages(), 0, 'object a dump_status_messages() is 0');
is(ChildB->dump_status_messages(), 0, 'ChildB dump_status_messages() is 0');
is($b->dump_status_messages(), 0, 'object b dump_status_messages() is 0');

# All the class' dump flags are initialized, change the parent shouldn't change the child
is(Parent->dump_status_messages(1), 1, 'Change Parent dump_status_messages() to 1');
is(ChildA->dump_status_messages(), 0, 'ChildA dump_status_messages() is still 0');
is($a->dump_status_messages(), 0, 'object a dump_status_messages() is still 0');
is(ChildB->dump_status_messages(), 0, 'ChildB dump_status_messages() is still 0');
is($b->dump_status_messages(), 0, 'object b dump_status_messages() is still 0');

is(ChildA->dump_status_messages(1), 1, 'Change ChildA class dump_status_messages to 1');
is($a->dump_status_messages(), 0, 'object a dump_status_messages() is still 0');
is(ChildB->dump_status_messages(), 0, 'ChildB dump_status_messages() is still 0');
is($b->dump_status_messages(), 0, 'object b dump_status_messages() is still 0');


