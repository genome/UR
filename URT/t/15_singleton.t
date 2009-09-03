use strict;
use warnings;
use Test::More tests =>  17;

use URT;

# The commented-out tests are things you might expect to work (and that we'd like
# to work), but aren't working at this time...

my $co = UR::Object::Type->define(
    class_name => 'URT::SomeSingleton',
    is => ['UR::Singleton'],
    has => [
        property_a => { is => 'String' },
    ],
);
ok($co, 'Defined URT::SomeSingleton class');

$co = UR::Object::Type->define(
    class_name => 'URT::ChildSingleton',
    is => [ 'URT::SomeSingleton' ],
    has => [
        property_b => { is => 'String' },
    ],
);
ok($co, 'Defined URT::ChildSingleton class');


my $obj = URT::SomeSingleton->_singleton_object();
ok($obj, 'Got the URT::SomeSingleton object through _singleton_object()');
isa_ok($obj, 'URT::SomeSingleton');

is($obj->property_a('hello'), 'hello', 'Setting property_a on URT::SomeSingleton object');
is($obj->property_a(), 'hello', 'Getting property_a on URT::SomeSingleton object');
#is(URT::SomeSingleton->property_a(), 'hello', 'Getting property_a on URT::SomeSingleton class');

#is(URT::SomeSingleton->property_a('there'), 'there', 'Setting property_a on URT::SomeSingleton class');
#is($obj->property_a(), 'there', 'Getting property_a on URT::SomeSingleton object');
#is(URT::SomeSingleton->property_a(), 'there', 'Getting property_a on URT::SomeSingleton class');

my $obj2 = URT::SomeSingleton->get();
ok($obj2, 'Calling get() on URT::SomeSingleton returns an object');
is_deeply($obj,$obj2, 'The two objects are the same');




$obj = URT::ChildSingleton->_singleton_object();
ok($obj, 'Got the URT::ChildSingleton object through _singleton_object()');
isa_ok($obj, 'URT::ChildSingleton');
isa_ok($obj, 'URT::SomeSingleton');

is($obj->property_a('foo'), 'foo', 'Setting property_a on URT::ChildSingleton object');
is($obj->property_a(), 'foo', 'Getting property_a on URT::ChildSingleton object');
#is(URT::ChildSingleton->property_a(), 'foo', 'Getting property_a on URT::ChildSingleton class');

#is(URT::ChildSingleton->property_a('bar'), 'bar', 'Setting property_a on URT::ChildSingleton class');
#is($obj->property_a(), 'bar', 'Getting property_a on URT::ChildSingleton object');
#is(URT::ChildSingleton->property_a(), 'bar', 'Getting property_a on URT::ChildSingleton class');


is($obj->property_b('blah'), 'blah', 'Setting property_b on URT::ChildSingleton object');
is($obj->property_b(), 'blah', 'Getting property_b on URT::ChildSingleton object');
#is(URT::ChildSingleton->property_b(), 'blah', 'Getting property_b on URT::ChildSingleton class');


$obj2 = URT::ChildSingleton->get();
ok($obj2, 'Calling get() on URT::ChildSingleton returns an object');
is_deeply($obj,$obj2, 'The two objects are the same');







