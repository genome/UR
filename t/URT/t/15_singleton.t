use strict;
use warnings;
use Test::More tests => 21; 

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;

my $co = UR::Object::Type->define(
    class_name => 'URT::Parent',
);
ok($co, 'Defined a parent, non-singleton class');
    
$co = UR::Object::Type->define(
    class_name => 'URT::SomeSingleton',
    is => ['URT::Parent','UR::Singleton'],
    has => [
        property_a => { is => 'String' },
    ],
);
ok($co, 'Defined URT::SomeSingleton class');

$co = UR::Object::Type->define(
    class_name => 'URT::ChildSingleton',
    is => [ 'URT::SomeSingleton','UR::Singleton' ],
    has => [
        property_b => { is => 'String' },
    ],
);
ok($co, 'Defined URT::ChildSingleton class');

$co = UR::Object::Type->define(
    class_name => 'URT::GrandChild',
    is => [ 'URT::ChildSingleton'],
);
ok($co, 'Defined URT::GrandChild class');
ok(URT::GrandChild->create(id => '123', property_a => 'foo', property_b=>'bar'), 'Created a URT::GrandChild object');
   


my $obj = URT::SomeSingleton->_singleton_object();
ok($obj, 'Got the URT::SomeSingleton object through _singleton_object()');
isa_ok($obj, 'URT::SomeSingleton');

is($obj->property_a('hello'), 'hello', 'Setting property_a on URT::SomeSingleton object');
is($obj->property_a(), 'hello', 'Getting property_a on URT::SomeSingleton object');

my $obj2 = URT::SomeSingleton->get();
ok($obj2, 'Calling get() on URT::SomeSingleton returns an object');
is_deeply($obj,$obj2, 'The two objects are the same');




$obj = URT::ChildSingleton->_singleton_object();
ok($obj, 'Got the URT::ChildSingleton object through _singleton_object()');
isa_ok($obj, 'URT::ChildSingleton');
isa_ok($obj, 'URT::SomeSingleton');

is($obj->property_a('foo'), 'foo', 'Setting property_a on URT::ChildSingleton object');
is($obj->property_a(), 'foo', 'Getting property_a on URT::ChildSingleton object');

is($obj->property_b('blah'), 'blah', 'Setting property_b on URT::ChildSingleton object');
is($obj->property_b(), 'blah', 'Getting property_b on URT::ChildSingleton object');


$obj2 = URT::ChildSingleton->get();
ok($obj2, 'Calling get() on URT::ChildSingleton returns an object');
is_deeply($obj,$obj2, 'The two objects are the same');


my @objs = URT::Parent->get();
is(scalar(@objs), 3, 'get() via parent class returns 3 objects');






