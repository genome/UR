use strict;
use warnings;
use Test::More tests=> 3;
use Test::Exception;
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

subtest 'multiple roles' => sub {
    plan tests => 6;

    sub URT::FirstRole::first_method { 1 }
    role URT::FirstRole {
        has => [ 'first_property' ],
    };

    sub URT::SecondRole::second_method { 1 }
    role URT::SecondRole {
        has => [ 'second_property' ],
    };

    sub URT::ClassWithMultipleRoles::class_method { 1 }
    class URT::ClassWithMultipleRoles {
        has => ['class_property'],
        roles => ['URT::FirstRole', 'URT::SecondRole'],
    };

    ok(URT::ClassWithMultipleRoles->__meta__, 'Created class with multiple roles');
    foreach my $role_name ( qw( URT::FirstRole URT::SecondRole ) ) {
        ok(URT::ClassWithMultipleRoles->does($role_name), "Does $role_name");
    }

    foreach my $method_name ( qw( first_method second_method class_method ) ) {
        ok(URT::ClassWithMultipleRoles->can($method_name), "Can $method_name");
    }
};

subtest requires => sub {
    plan tests => 5;

    role URT::RequiresPropertyRole {
        has => [ 'role_property' ],
        requires => ['required_property'],
    };

    throws_ok
        {
            class URT::RequiresPropertyClass {
                has => [ 'foo' ],
                roles => 'URT::RequiresPropertyRole',
            }
        }
        qr/missing required property or method 'required_property'/,
        'Omitting a required property throws an exception';



    role URT::RequiresPropertyAndMethodRole {
        requires => ['required_method', 'required_property' ],
    };

    sub URT::RequiresPropertyAndMethodHasMethod::required_method { 1 }
    throws_ok
        {
            class URT::RequiresPropertyAndMethodHasMethod {
                has => ['foo'],
                roles => 'URT::RequiresPropertyAndMethodRole',
            }
        }
        qr/missing required property or method 'required_property'/,
        'Omitting a required property throws an exception';


    throws_ok
        {
            class URT::RequiresPropertyAndMethodHasProperty {
                has => ['required_property'],
                roles => 'URT::RequiresPropertyAndMethodRole',
            }
        }
        qr/missing required property or method 'required_method'/,
        'Omitting a required method throws an exception';


    sub URT::RequiesPropertyAndMethodHasBoth::required_method { 1 }
    lives_ok
        {
            class URT::RequiesPropertyAndMethodHasBoth {
                has => ['required_property'],
                roles => 'URT::RequiresPropertyAndMethodRole',
            }
        }
        'Created class satisfying requirements';

    role URT::RequiresPropertyFromOtherRole {
        requires => ['role_property'],
    };

    lives_ok
        {
            class URT::RequiresBothRoles {
                has => ['required_property'],
                roles => ['URT::RequiresPropertyRole', 'URT::RequiresPropertyFromOtherRole'],
            }
        }
        'Created class with role requiring method from other role';

};
