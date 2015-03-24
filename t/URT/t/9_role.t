use strict;
use warnings;
use Test::More tests=> 13;
use Test::Exception;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

use URT;

subtest basic => sub {
    plan tests => 12;

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

    throws_ok { URT::BasicRole->create() }
        qr(Can't locate object method "create" via package "URT::BasicRole"),
        'Trying to create() a role by package name throws an exception';

    throws_ok { URT::BasicRole->get() }
        qr(Can't locate object method "get" via package "URT::BasicRole"),
        'Trying to get() a role by package name throws an exception';
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

subtest 'inherits from class with role' => sub {
    plan tests => 5;

    role ParentClassRole {
        has => ['parent_role_param'],
    };
    sub ParentClass::parent_class_method { 1 }
    class ParentClass {
        roles => ['ParentClassRole'],
        has => ['parent_class_param'],
    };

    class ChildClass {
        is => 'ParentClass',
    };

    role GrandchildClassRole {
        has => ['grandchild_role_param'],
        requires => ['parent_class_param', 'parent_class_method'],
    };

    class GrandchildClass {
        is => 'ChildClass',
        roles => ['GrandchildClassRole'],
    };

    my $o = GrandchildClass->create(parent_class_param => 1,
                                    parent_role_param => 1,
                                    grandchild_role_param => 1);
    ok($o, 'Create object');
    ok($o->can('grandchild_role_param'), 'can grandchild_role_param');
    ok($o->can('parent_role_param'), 'can parent_role_param');
    ok($o->does('GrandchildClassRole'), 'does GrandchildClassRole');
    ok($o->does('ParentClassRole'), 'does ParentClassRole');
};

subtest 'role property saves to DB' => sub {
    plan tests => 10;

    my $dbh = URT::DataSource::SomeSQLite->get_default_handle;
    ok($dbh->do(q(CREATE TABLE savable (id INTEGER NOT NULL PRIMARY KEY, class_property TEXT, role_property TEXT))),
        'Create table');
    ok($dbh->do(q(INSERT INTO savable VALUES (1, 'class', 'role'))),
        'Insert row');

    role SavablePropertyRole {
        has => ['role_property'],
    };
    class SavableToDb {
        roles => 'SavablePropertyRole',
        id_by => 'id',
        has => ['class_property'],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'savable',
    };

    foreach my $prop ( qw( class_property role_property ) ) {
        ok(SavableToDb->can($prop), "SavableToDb can $prop");
    }

    my $got = SavableToDb->get(1);
    ok($got, 'Get object from DB');
    is($got->class_property, 'class', 'class_property value');
    is($got->role_property, 'role', 'role_property value');

    my $saved = SavableToDb->create(id => 2, class_property => 'saved_class', role_property => 'saved_role');
    ok($saved, 'Create object');
    ok(UR::Context->commit(), 'commit');

    my $row = $dbh->selectrow_hashref('SELECT * from savable where id = 2');
    is_deeply($row,
              { id => 2, class_property => 'saved_class', role_property => 'saved_role' },
              'saved to the DB');
};

subtest 'role import function' => sub {
    plan tests => 8;

    my($import_called, @import_args) = (0, ());
    *RoleWithImport::__import__  = sub { $import_called++; @import_args = @_ };
    role RoleWithImport { };
    sub RoleWithImport::another_method { 1 }

    is($import_called, 0, '__import__ was not called after defining role');

    class ClassWithImport {
        roles => ['RoleWithImport'],
    };
    is($import_called, 1, '__import__ called when role is used');
    is_deeply(\@import_args,
              [ 'RoleWithImport', ClassWithImport->__meta__ ],
              '__import__called with role name and class meta as args');
    ok(! defined(&ClassWithImport::__import__), '__import__ was not imported into the class namespace');


    $import_called = 0;
    @import_args = ();
    class AnotherClassWithImport {
        roles => ['RoleWithImport'],
    };
    is($import_called, 1, '__import__ called when role is used again');
    is_deeply(\@import_args,
              [ 'RoleWithImport', AnotherClassWithImport->__meta__ ],
              '__import__called with role name and class meta as args');
    ok(! defined(&ClassWithImport::__import__), '__import__ was not imported into the class namespace');


    $import_called = 0;
    @import_args = ();
    class ChildClassWithImport {
        is => 'ClassWithImport',
    };

    is($import_called, 0, '__import__ was not called when a child class is defined');
};

subtest 'basic overloading' => sub {
    plan tests => 5;

    package OverloadingAddRole;
    use overload '+' => '_add_return_zero';
    our $add_called = 0;
    sub OverloadingAddRole::_add_return_zero {
        my($self, $other) = @_;
        $add_called++;
        return 0;
    }
    role OverloadingAddRole { };

    package OverloadingSubRole;
    use overload '-' => \&OverloadingRole::_sub_return_zero;
    our $sub_called = 0;
    sub OverloadingRole::_sub_return_zero {
        my($self, $other) = @_;
        $sub_called++;
        return 0;
    }
    role OverloadingSubRole { };

    package main;
    class OverloadingClass {
        roles => [qw( OverloadingAddRole OverloadingSubRole )],
    };

    my $o = OverloadingClass->create();
    ok(defined($o), 'Create object from class with overloading role');
    is($o + 1, 0, 'Adding to object returns overloaded value');
    is($OverloadingAddRole::add_called, 1, 'overloaded add called');

    is($o - 1, 0, 'Adding to object returns overloaded value');
    is($OverloadingSubRole::sub_called, 1, 'overloaded subtract called');
};

subtest 'overload fallback' => sub {
    plan tests => 6;

    package RoleWithOverloadFallbackFalse;
    use overload '+' => 'add_overload',
                fallback => 0;
    role RoleWithOverloadFallbackFalse { };
    sub add_overload { }

    package AnotherRoleWithOverloadFallbackFalse;
    use overload '-' => 'sub_overload',
                fallback => 0;
    role AnotherRoleWithOverloadFallbackFalse { };
    sub sub_overload { }

    package RoleWithOverloadFallbackTrue;
    use overload '*' => 'mul_overload',
                fallback => 1;
    role RoleWithOverloadFallbackTrue { };
    sub mul_overload { }

    package AnotherRoleWithOverloadFallbackTrue;
    use overload '/' => 'div_overload',
                fallback => 1;
    role AnotherRoleWithOverloadFallbackTrue { };
    sub div_overload { }

    package RoleWithOverloadFallbackUndef;
    use overload '""' => 'str_overload',
                fallback => undef;
    role RoleWithOverloadFallbackUndef { };
    sub str_overload { }

    package AnotherRoleWithOverloadFallbackUndef;
    use overload '%' => 'mod_overload';
    role AnotherRoleWithOverloadFallbackUndef { };
    sub mod_overload { }

    package main;
    lives_ok {
        class ClassWithMatchingFallbackFalse {
            roles => ['RoleWithOverloadFallbackFalse', 'AnotherRoleWithOverloadFallbackFalse'],
        } }
        'Composed two classes with overload fallback false';

    lives_ok {
        class ClassWithMatchingFallbackTrue {
            roles => ['RoleWithOverloadFallbackTrue', 'AnotherRoleWithOverloadFallbackTrue'],
        } }
        'Composed two classes with overload fallback true';

    lives_ok {
        class ClassWithMatchingFallbackUndef {
            roles => ['RoleWithOverloadFallbackUndef', 'AnotherRoleWithOverloadFallbackUndef'],
        }}
        'Composed wto classes with overload fallback undef';

    lives_ok {
        class ClassWithOneFallbackFalse {
            roles => ['RoleWithOverloadFallbackFalse', 'RoleWithOverloadFallbackUndef'],
        }}
        'Composed one role with fallback false and one fallback undef';

    lives_ok {
        class ClassWithOneFallbackTrue {
            roles => ['RoleWithOverloadFallbackTrue', 'RoleWithOverloadFallbackUndef'],
        }}
        'Composed one role with fallback true and one fallback undef';

    throws_ok {
        class ClassWithConflictFallback {
            roles => ['RoleWithOverloadFallbackFalse', 'RoleWithOverloadFallbackTrue'],
        }}
        qr(fallback value '1' conflicts with fallback value 'FALSE' in role RoleWithOverloadFallbackFalse),
        'Overload fallback conflict throws exception';
};

subtest 'overload conflict' => sub {
    plan tests => 5;

    package OverloadConflict1;
    use overload '+' => '_foo';
    role OverloadConflict1 { };
    sub OverloadConflict1::_foo { }

    package OverloadConflict2;
    use overload '+' => '_bar';
    role OverloadConflict2 { };
    sub OverloadConflict1::_bar { }

    package main;
    throws_ok { class OverloadConflictClass {
                    roles => [qw( OverloadConflict1 OverloadConflict2 )],
                } }
        qr(Cannot compose role OverloadConflict2: Overload '\+' conflicts with overload in role OverloadConflict1),
        'Roles with conflicting overrides cannot be composed together';


    package OverloadConflictResolvedClass;
    our $overload_called = 0;
    use overload '+' => sub { $overload_called++; return 'Overloaded' };

    package main;
    lives_ok
        {
            class OverloadConflictResolvedClass {
                roles => [qw( OverloadConflict1 OverloadConflict2 )],
        } }
        'Class with overrides composes both roles with overrides';

    my $o = OverloadConflictResolvedClass->create();
    ok(defined($o), 'Created instance');
    is($o + 1, 'Overloaded', 'overloaded method called');
    is($OverloadConflictResolvedClass::overload_called, 1, 'overload method called once');
};

subtest 'excludes' => sub {
    plan tests => 3;

    role Excluded { };
    role Excluder { excludes => ['Excluded'] };
    role NotExcluded { };

    lives_ok
        {
            class ExcludeClassWorks { roles => ['Excluder', 'NotExcluded'] };
        }
        'Define class with exclusion role not triggered';

    throws_ok
        {
            class ExcludeClass { roles => ['Excluded', 'Excluder'] };
        }
        qr(Cannot compose role Excluded into class ExcludeClass: Role Excluder excludes it),
        'Composing class with excluded role throws exception';

    throws_ok
        {
            class ExcludeClass2 { roles => ['Excluder', 'Excluded'] };
        }
        qr(Cannot compose role Excluded into class ExcludeClass2: Role Excluder excludes it),
        'Composing excluded roles in the other order also throws exception';
};
