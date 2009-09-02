use strict;
use warnings;
use Test::More 'no_plan';
my ($obj,$same_obj);

use UR;

UR::Object::Type->define(
    class_name => 'Acme::Product',
    has => [qw/name manufacturer_name/,
        'short_name'
    ]
);

$obj = Acme::Product->create(name => "dynamite", manufacturer_name => "Explosives R US", short_name => "Exp");

is($obj->name, "dynamite");
is($obj->manufacturer_name, "Explosives R US");
is($obj->short_name, "Exp");

$same_obj = Acme::Product->get(name => "dynamite");

is($obj,$same_obj);

