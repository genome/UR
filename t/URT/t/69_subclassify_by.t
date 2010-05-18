use warnings;
use strict;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use UR;
use Test::More tests => 40;

UR::Object::Type->define(
    class_name => 'Acme',
    is => ['UR::Namespace'],
);

our $calculate_called = 0;
UR::Object::Type->define(
    class_name => 'Acme::Employee',
    subclassify_by => 'subclass_name',
    is_abstract => 1,
    has => [
        name => { type => "String" },
        subclass_name => { type => 'String' },
    ],
);

UR::Object::Type->define(
    class_name => 'Acme::Employee::Worker',
    is => 'Acme::Employee',
);

UR::Object::Type->define(
    class_name => 'Acme::Employee::Boss',
    is => 'Acme::Employee',
);

my $e1 = eval { Acme::Employee->create(name => 'Bob') };
ok(! $e1, 'Unable to create an object from the abstract class');
like($@, qr/abstract class requires param 'subclass_name' to be specified/, 'The exception was correct');

$e1 = Acme::Employee->create(name => 'Bob', subclass_name => 'Acme::Employee::Worker');
ok($e1, 'Created an object from the base class and specified subclass_name');
isa_ok($e1, 'Acme::Employee::Worker');
is($e1->name, 'Bob', 'Name is correct');
is($e1->subclass_name, 'Acme::Employee::Worker', 'subclass_name is correct');

$e1 = Acme::Employee::Worker->create(name => 'Bob2');
ok($e1, 'Created an object from a subclass without subclass_name');
isa_ok($e1, 'Acme::Employee::Worker');
is($e1->name, 'Bob2', 'Name is correct');
is($e1->subclass_name, 'Acme::Employee::Worker', 'subclass_name is correct');

$e1 = Acme::Employee->create(name => 'Fred', subclass_name => 'Acme::Employee::Boss');
ok($e1, 'Created an object from the base class and specified subclass_name');
isa_ok($e1, 'Acme::Employee::Boss');
is($e1->name, 'Fred', 'Name is correct');
is($e1->subclass_name, 'Acme::Employee::Boss', 'subclass_name is correct');

$e1 = Acme::Employee::Boss->create(name => 'Fred2');
ok($e1, 'Created an object from a subclass without subclass_name');
isa_ok($e1, 'Acme::Employee::Boss');
is($e1->name, 'Fred2', 'Name is correct');
is($e1->subclass_name, 'Acme::Employee::Boss', 'subclass_name is correct');

$e1 = Acme::Employee::Boss->create(name => 'Fred3', subclass_name => 'Acme::Employee::Boss');
ok($e1, 'Created an object from a subclass and specified the same subclass_name');
isa_ok($e1, 'Acme::Employee::Boss');
is($e1->name, 'Fred3', 'Name is correct');
is($e1->subclass_name, 'Acme::Employee::Boss', 'subclass_name is correct');



$e1 = eval { Acme::Employee::Worker->create(name => 'Joe', subclass_name => 'Acme::Employee') };
ok(! $e1, 'Creating an object from a subclass with the base class as subclass_name did not work');
like($@,
     qr/Value for subclassifying param 'subclass_name' \(Acme::Employee\) does not match the class it was called on \(Acme::Employee::Worker\)/,
     'Exception was correct');

$e1 = eval { Acme::Employee::Worker->create(name => 'Joe', subclass_name => 'Acme::Employee::Boss') };
ok(! $e1, 'Creating an object from a subclass with another subclass as subclass_name did not work');
like($@,
     qr/Value for subclassifying param 'subclass_name' \(Acme::Employee::Boss\) does not match the class it was called on \(Acme::Employee::Worker\)/,
     'Exception was correct');

$e1 = eval { Acme::Employee::Boss->create(name => 'Joe', subclass_name => 'Acme::Employee::Worker') };
ok(! $e1, 'Creating an object from a subclass with another subclass as subclass_name did not work');
like($@,
     qr/Value for subclassifying param 'subclass_name' \(Acme::Employee::Worker\) does not match the class it was called on \(Acme::Employee::Boss\)/,
     'Exception was correct');

$e1 = eval { Acme::Employee->create(name => 'Mike', subclass_name => 'Acme::Employee::NonExistent') };
ok(! $e1, 'Creating an object from the base class and gave invalid subclass_name did not work');
like($@,
     qr/Class Acme::Employee::NonExistent is not a subclass of Acme::Employee/,
     'Exception was correct');




