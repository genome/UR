#!/usr/bin/env perl

use strict;
use warnings;
use URT;
use Test::More tests => 22;

UR::Object::Type->define(
    class_name => 'URT::Person',
    has => [
        first_name  => { is => 'String' },
        last_name   => { is => 'String' },
        full_name   => {
            is => 'String',
            calculate_from => ['first_name','last_name'],
            calculate => '$first_name . " " . $last_name',
        }
    ]
);

my $p1 = URT::Person->create(
    first_name => "John", last_name => "Doe"
);
ok($p1, "Made a person");

my $p2 = URT::Person->create(
    first_name => "Jane", last_name => "Doe"
);
ok($p2, "Made another person");

my $callback_count1 = 0;
my $callback_count2 = 0;
my $callback_count3 = 0;

$p1->last_name("DoDo");
is($callback_count1+$callback_count2+$callback_count3, 0, "no callback count change with no observer");

my $o1 = $p1->add_observer(callback => sub { $callback_count1++});
ok($o1, "made an observer on person 1");

my $o2 = $p2->add_observer(callback => sub { $callback_count2++ });
ok($o2, "made an observer on person 2");

my $o3 = URT::Person->add_observer(callback => sub { $callback_count3++ });
ok($o2, "made an observer on for the class");

is($p1->last_name("Doh!"),"Doh!", "changed person 1");
is($callback_count1, 1, "callback registered for person 1");
is($callback_count2, 0, "no callback registered for person 2");
is($callback_count3, 1, "callback registered for class");
$callback_count1 = $callback_count2 = $callback_count3 = 0;

is($p2->last_name("Do"),"Do", "changed person 2");
is($callback_count1, 0, "callback registered for person 1");
is($callback_count2, 1, "no callback registered for person 2");
is($callback_count3, 1, "callback registered for class");
$callback_count1 = $callback_count2 = $callback_count3 = 0;

$o1->delete;

is($p1->last_name("Doooo"),"Doooo", "changed person 1");
is($callback_count1, 0, "no callback registered for person 1");
is($callback_count2, 0, "no callback registered for person 2");
is($callback_count3, 1, "callback registered for class");
$callback_count1 = $callback_count2 = $callback_count3 = 0;


is($p2->last_name("Boo"),"Boo", "changed person 2");
is($callback_count1, 0, "callback registered for person 1");
is($callback_count2, 1, "no callback registered for person 2");
is($callback_count3, 1, "callback registered for class");
$callback_count1 = $callback_count2 = $callback_count3 = 0;


