use strict;
use warnings;
use Test::More tests => 194;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

my @obj;

use UR;
use URT;

# memory-only class
UR::Object::Type->define(
    class_name => 'Acme::Product',
    has => [qw/name manufacturer_name genius/]
);

# same properties, but in the DB
my $dbh = URT::DataSource::SomeSQLite->get_default_handle;
$dbh->do('create table product (product_id integer NOT NULL PRIMARY KEY, name varchar, genius integer, manufacturer_name varchar)')
    or die "Can't create product table";

UR::Object::Type->define(
    class_name => 'Acme::DBProduct',
    id_by => 'product_id',
    has => [qw/name manufacturer_name genius/],
    table_name => 'product',
    data_source => 'URT::DataSource::SomeSQLite',
);


my @products = (
    [ name => "jet pack",     genius => 6,    manufacturer_name => "Lockheed Martin" ],
    [ name => "hang glider",  genius => 4,    manufacturer_name => "Boeing"],
    [ name => "mini copter",  genius => 5,    manufacturer_name => "Boeing"],
    [ name => "catapult",     genius => 5,    manufacturer_name => "Boeing"],
    [ name => "firecracker",  genius => 6,    manufacturer_name => "Explosives R US"],
    [ name => "dynamite",     genius => 9,    manufacturer_name => "Explosives R US"],
    [ name => "plastique",    genius => 8,    manufacturer_name => "Explosives R US"],
);

my $insert = $dbh->prepare('insert into product values (?,?,?,?)');
my $id = 1;
foreach ( @products ) {
    Acme::Product->create(@$_);
    $insert->execute($id++, @$_[1,3,5])
}
$insert->finish();
$dbh->commit();

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

for my $class ( qw( Acme::Product Acme::DBProduct ) ) {
    # Test with get()
    for (my $testnum = 0; $testnum < @tests; $testnum++) {
        my $params = $tests[$testnum]->[0];
        my $expected = $tests[$testnum]->[1];
        my @objs = $class->get(@$params);
        is(scalar(@objs), $expected, "Got $expected objects for get() test $testnum: ".join(' ', @$params));
    }

    # Test old syntax
    for (my $testnum = 0; $testnum < @tests; $testnum++) {
        my $params = $tests[$testnum]->[0];
        my $expected = $tests[$testnum]->[1];

        my %params;
        for(my $i = 0; $i < @$params; $i += 2) {
            my($prop, undef, $op) = $params->[$i] =~ m/^(\w+)(\s+(.*))?/;
            $params{$prop} = { operator => $op, value => $params->[$i+1] };
        }
        my @objs = $class->get(%params);
        is(scalar(@objs), $expected, "Got $expected objects for get() old syntax test $testnum: ".join(' ', @$params));
    }

    # test get with a bx
    for (my $testnum = 0; $testnum < @tests; $testnum++) {
        my $params = $tests[$testnum]->[0];
        my $expected = $tests[$testnum]->[1];
        my $bx = $class->define_boolexpr(@$params);
        my @objs = $class->get($bx);
        is(scalar(@objs), $expected, "Got $expected objects for bx test $testnum: ".join(' ', @$params));

        # test each param in the BX
        my %params = @$params;
        foreach my $key ( keys %params ) {
            ($key) = $key =~ m/(\w+)/;
            ok($bx->specifies_value_for($key), "bx does specify value for $key");
        }
    }
}
