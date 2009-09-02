use warnings;
use strict;

use UR;
use Test::More tests => 12;

UR::Object::Type->define(
    class_name => 'Acme',
    is => ['UR::Namespace'],
);

UR::Object::Type->define(
    class_name => "Acme::Boss",
    has => [
        id      => { type => "Number" },
        name    => { type => "String" },
        company => { type => "String" },
    ]
);

UR::Object::Type->define(
    class_name => 'Acme::Employee',
    has => [
        name => { type => "String" },
        boss => { type => "Acme::Boss", id_by => 'boss_id' },
        boss_name => { via => 'boss', to => 'name' },
        company   => { via => 'boss' },
    ]
);

my $b1 = Acme::Boss->create(name => "Bosser", company => "Some Co.");
ok($b1, "created a boss object");
my $e1 = Acme::Employee->create(boss => $b1);
ok($e1, "created an employee object");
ok($e1->can("boss_name"), "employees can check their boss' name");
ok($e1->can("company"), "employees can check their boss' company");

is($e1->boss_name,$b1->name, "boss_name check works");
is($e1->company,$b1->company, "company check works");

$b1->name("Crabber");
$b1->company("Other Co.");
is($e1->boss_name,$b1->name, "boss_name check works again");
is($e1->company,$b1->company, "company check still works");

my $b2 = Acme::Boss->create(name => "Chief", company => "Yet Another Co.");
ok($b2, "made another boss");
$e1->boss($b2);
is($e1->boss,$b2, "re-assigned the employee to a new boss");
is($e1->boss_name,$b2->name, "boss_name check works");
is($e1->company,$b2->company, "company check works");

