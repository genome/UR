use strict;
use warnings;
use Test::More 'no_plan';
my ($p1,$p2,$p3,$p4,$p5,$p6,$p7,@obj); 

use UR;

UR::Object::Type->define(
    class_name => 'Acme::Product',
    has => [qw/name manufacturer_name genius/]
);

$p1 = Acme::Product->create(name => "jet pack",     genius => 6,    manufacturer_name => "Lockheed Martin");
$p2 = Acme::Product->create(name => "hang glider",  genius => 4,    manufacturer_name => "Boeing");
$p3 = Acme::Product->create(name => "mini copter",  genius => 5,    manufacturer_name => "Boeing");
$p4 = Acme::Product->create(name => "firecracker",  genius => 6,    manufacturer_name => "Explosives R US");
$p5 = Acme::Product->create(name => "dynamite",     genius => 7,    manufacturer_name => "Explosives R US");
$p6 = Acme::Product->create(name => "plastique",    genius => 8,    manufacturer_name => "Explosives R US");
$p7 = Acme::Product->create(name => "mega copter",  genius => 2,    manufacturer_name => "Cheap Chopper");

@obj = Acme::Product->get(name => { operator => "like", value => '%copter' });
is(scalar(@obj),2);

@obj = Acme::Product->get(genius => { operator => ">=", value => 6 });
is(scalar(@obj),4);

@obj = Acme::Product->get(genius => { operator => "between", value => [5,7] });
is(scalar(@obj),4);

@obj = sort Acme::Product->get(name => { operator => "not in", value => ['jet pack', 'dynamite'] });
is(scalar(@obj),5);

 
