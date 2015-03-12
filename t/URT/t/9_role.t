use strict;
use warnings;
use Test::More tests=> 6;
use Test::Exception;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

use URT;

subtest basic => sub {
    plan tests => 10;

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

    throws_ok
        {
            class URT::ClassWithBogusRole {
                roles => ['Bogus'],
            }
        }
        qr(Cannot dynamically load role 'Bogus': No module exists with that name\.),
        'Could not create class with a bogus role';
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

subtest 'conflict property' => sub {
    plan tests => 5;

    role URT::ConflictPropertyRole1 {
        has => [
            conflict_property => { is => 'RoleProperty' },
        ],
    };
    role URT::ConflictPropertyRole2 {
        has => [
            other_property => { is => 'Int' },
            conflict_property => { is => 'RoleProperty' },
        ],
    };
    throws_ok
        {
            class URT::ConflictPropertyClass {
                roles => ['URT::ConflictPropertyRole1', 'URT::ConflictPropertyRole2'],
            }
        }
        qr/Cannot compose role URT::ConflictPropertyRole2: Property 'conflict_property' conflicts with property in role URT::ConflictPropertyRole1/,
        'Composing two roles with the same property throws exception';


    throws_ok
        {
            class URT::ConflictPropertyClassWithProperty {
                has => ['conflict_property'],
                roles => ['URT::ConflictPropertyRole1', 'URT::ConflictPropertyRole2'],
            }
        }
        qr/Cannot compose role URT::ConflictPropertyRole2: Property 'conflict_property' conflicts with property in role URT::ConflictPropertyRole1/,
        'Composing two roles with the same property throws exception even if class has override property';

    sub URT::ConflictPropertyClassWithMethod::conflict_property { 1 }
    throws_ok
        {
            class URT::ConflictPropertyClassWithMethod {
                roles => ['URT::ConflictPropertyRole1', 'URT::ConflictPropertyRole2'],
            }
        }
        qr/Cannot compose role URT::ConflictPropertyRole2: Property 'conflict_property' conflicts with property in role URT::ConflictPropertyRole1/,
        'Composing two roles with the same property throws exception even if class has override method';


    lives_ok
        {
            class URT::ConflictPropertyClassWithProperty {
                has => [
                    conflict_property => { is => 'ClassProperty' },
                ],
                roles => ['URT::ConflictPropertyRole1'],
            }
        }
        'Composed role into class sharing property name';
    my $prop_meta = URT::ConflictPropertyClassWithProperty->__meta__->property('conflict_property');
    is($prop_meta->data_type, 'ClassProperty', 'Class gets the class-defined property');
};

subtest 'conflict methods' => sub {
    plan tests => 4;

    sub URT::ConflictMethodRole1::conflict_method { }
    role URT::ConflictMethodRole1 { };

    sub URT::ConflictMethodRole2::conflict_method { }
    role URT::ConflictMethodRole2 { };

    throws_ok
        {
            class URT::ConflictMethodClassMissingMethod {
                roles => ['URT::ConflictMethodRole1', 'URT::ConflictMethodRole2'],
            }
        }
        qr/Cannot compose role URT::ConflictMethodRole2: method conflicts with those defined in other roles\s+URT::ConflictMethodRole1::conflict_method/s,
        'Composing two roles with the same method throws exception';


    our $class_method_called = 0;
    sub URT::ConflictMethodClassHasMethod::conflict_method { $class_method_called++; 1; }
    lives_ok
        {
            class URT::ConflictMethodClassHasMethod {
                roles => ['URT::ConflictMethodRole1', 'URT::ConflictMethodRole2'],
            }
        }
        'Composed two roles with the same method into class with same method';
    ok(URT::ConflictMethodClassHasMethod->conflict_method, 'Called conflict_method on the class');
    is($class_method_called, 1, 'Correct method was called');
};

subtest 'dynamic loading' => sub {
    plan tests => 4;

    sub URT::DynamicLoading::required_class_method { 1 }
    my $class =  class URT::DynamicLoading {
        has => ['required_class_param'],
        roles => ['URT::TestRole'],
    };
    ok($class, 'Created class with dynamically loaded role');
    ok($class->role_method, 'called role_method on the class');

    throws_ok { class URT::DynamicLoadingFail1 { roles => 'URT::NotExistant' } }
        qr/Cannot dynamically load role 'URT::NotExistant': No module exists with that name\./,
        'Defining class with non-existant role throws exception';

    throws_ok { class URT::DynamicLoadingFail2 { roles => 'URT::Thingy' } }
        qr/Cannot dynamically load role 'URT::Thingy': The module loaded but did not define a role\./,
        'Defing a class with a class name used as a role throws exception';
};
