use strict;
use warnings;
use Test::More tests=> 1;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

use URT;

subtest basic => sub {
    plan tests => 9;

    role URT::BasicRole {
        has => [
            role_property => { is => 'String' },
        ],
        requires => [ 'required_property', 'required_method' ],
        excludes => [ ],
    };

    sub URT::BasicRole::role_method { 1 }

    class URT::BasicClass {
        has => [ 'regular_property', 'required_property' ],
        roles => 'URT::BasicRole',
    };

    sub URT::BasicClass::required_method { 1 }

    ok(URT::BasicClass->__meta__, 'BasicClass exists');
    ok(URT::BasicClass->does('URT::BasicRole'), 'BasicClass does() BasicRole');
    ok(! URT::BasicClass->does('URT::BasicClass'), "BasicClass doesn't() BasicClass");
    ok(! URT::BasicClass->does('Garbage'), "BasicClass doesn't() Garbage");

    my $o = URT::BasicClass->create(required_property => 1, role_property => 1, regular_property => 1);
    foreach my $method ( qw( required_property role_property regular_property role_method required_method ) ) {
        ok($o->$method, "call $method");
    }
};
