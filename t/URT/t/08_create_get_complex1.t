use strict;
use warnings;
use Test::More tests => 73;
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

my @tests = (
                # get params                                # num expected objects
    [ [ manufacturer_name => 'Boeing', genius => 5],            2 ],
    [ [ name => ['jet pack', 'dynamite'] ],                     2 ],
    [ [ manufacturer_name => ['Boeing','Lockheed Martin'] ],    4 ],
    [ [ 'genius !=' => 9 ],                                     6 ],
    [ [ 'genius not' => 9 ],                                    6 ],
    [ [ 'genius not =' => 9 ],                                  6 ],
    [ [ 'manufacturer_name !=' => 'Explosives R US' ],          4 ],
    [ [ 'manufacturer_name like' => '%arti%' ],                 1 ],
    [ [ 'manufacturer_name not like' => '%arti%' ],             6 ],
    [ [ 'genius <' => 6 ],                                      3 ],
    [ [ 'genius !<' => 6 ],                                     4 ],
    [ [ 'genius not <' => 6 ],                                  4 ],
    [ [ 'genius <=' => 6 ],                                     5 ],
    [ [ 'genius !<=' => 6 ],                                    2 ],
    [ [ 'genius not <=' => 6 ],                                 2 ],
    [ [ 'genius >' => 6 ],                                      2 ],
    [ [ 'genius !>' => 6 ],                                     5 ],
    [ [ 'genius not >' => 6 ],                                  5 ],
    [ [ 'genius >=' => 6 ],                                     4 ],
    [ [ 'genius !>=' => 6 ],                                    3 ],
    [ [ 'genius not >=' => 6 ],                                 3 ],
    [ [ 'genius between' => [4,6] ],                            5 ],
    [ [ 'genius !between' => [4,6] ],                           2 ],
    [ [ 'genius not between' => [4,6] ],                        2 ],
);
# Test with get()
for (my $testnum = 0; $testnum < @tests; $testnum++) {
    my $params = $tests[$testnum]->[0];
    my $expected = $tests[$testnum]->[1];
    my @objs = Acme::Product->get(@$params);
    is(scalar(@objs), $expected, "Got $expected objects for get() test $testnum: ".join(' ', @$params));
}

# test get with a bx
for (my $testnum = 0; $testnum < @tests; $testnum++) {
    my $params = $tests[$testnum]->[0];
    my $expected = $tests[$testnum]->[1];
    my $bx = Acme::Product->define_boolexpr(@$params);
    my @objs = Acme::Product->get($bx);
    is(scalar(@objs), $expected, "Got $expected objects for bx test $testnum: ".join(' ', @$params));

    # test each param in the BX
    my %params = @$params;
    foreach my $key ( keys %params ) {
        ($key) = $key =~ m/(\w+)/;
        ok($bx->specifies_value_for($key), "bx does specify value for $key");
    }
}

