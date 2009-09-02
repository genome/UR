use strict;
use warnings;
use Test::More 'no_plan';
my ($p1,$p2,$p3,$p4,$p5,$p6,$p7,@obj,@got,@expected);

use UR;

UR::Object::Type->define(
    class_name => 'Acme::Product',
    has => [qw/name manufacturer_name/]
);

$p1 = Acme::Product->create(name => "jet pack",     manufacturer_name => "Lockheed Martin");
$p2 = Acme::Product->create(name => "hang glider",  manufacturer_name => "Boeing");
$p3 = Acme::Product->create(name => "mini copter",  manufacturer_name => "Boeing");
$p4 = Acme::Product->create(name => "firecracker",  manufacturer_name => "Explosives R US");
$p5 = Acme::Product->create(name => "dynamite",     manufacturer_name => "Explosives R US");
$p6 = Acme::Product->create(name => "plastique",    manufacturer_name => "Explosives R US");

@obj = Acme::Product->get(manufacturer_name => "Boeing");
is(scalar(@obj), 2);

#

@obj = Acme::Product->get();
is(scalar(@obj), 6);

@got        = sort @obj;
@expected   = sort ($p1,$p2,$p3,$p4,$p5,$p6);
is_deeply(\@got,\@expected);

