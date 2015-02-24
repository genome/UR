use strict;
use warnings;
use Test::More tests=> 9;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

use URT;

role URT::TestRole {
    has => [
        role_property => { is => 'String' },
    ],
    requires => [ 'required_property', 'required_method' ],
    excludes => [ ],
};

sub URT::TestRole::role_method { 1 }

class URT::TestClass {
    has => [ 'regular_property', 'required_property' ],
    roles => 'URT::TestRole',
};

sub URT::TestClass::required_method { 1 }

ok(URT::TestClass->__meta__, 'TestClass exists');
ok(URT::TestClass->does('URT::TestRole'), 'TestClass does() TestRole');
ok(! URT::TestClass->does('URT::TestClass'), "TestClass doesn't() TestClass");
ok(! URT::TestClass->does('Garbage'), "TestClass doesn't() Garbage");

my $o = URT::TestClass->create(required_property => 1, role_property => 1, regular_property => 1);
foreach my $method ( qw( required_property role_property regular_property role_method required_method ) ) {
    ok($o->$method, "call $method");
}
