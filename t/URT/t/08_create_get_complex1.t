use strict;
use warnings;
use Test::More tests => 3;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

my @obj;

use UR;

UR::Object::Type->define(
    class_name => 'Acme::Product',
    has => [qw/name manufacturer_name genius/]
);

Acme::Product->create(name => "jet pack",     genius => 6,    manufacturer_name => "Lockheed Martin");
Acme::Product->create(name => "hang glider",  genius => 4,    manufacturer_name => "Boeing");
Acme::Product->create(name => "mini copter",  genius => 5,    manufacturer_name => "Boeing");
Acme::Product->create(name => "catapult",     genius => 5,    manufacturer_name => "Boeing");
Acme::Product->create(name => "firecracker",  genius => 6,    manufacturer_name => "Explosives R US");
Acme::Product->create(name => "dynamite",     genius => 9,    manufacturer_name => "Explosives R US");
Acme::Product->create(name => "plastique",    genius => 8,    manufacturer_name => "Explosives R US");

@obj = Acme::Product->get(manufacturer_name => 'Boeing', genius => 5);
is(scalar(@obj),2, "Two objects match manufacturer_name => 'Boeing', genius => 5");

@obj = Acme::Product->get(name => ['jet pack', 'dynamite']);
is(scalar(@obj),2, 'Two object match name "jet pack" or "dynamite"');

@obj = Acme::Product->get(manufacturer_name => ['Boeing','Lockheed Martin']);
is(scalar(@obj),4, '4 objects have manufacturer_name Boeing or Lockheed Martin');

