use strict;
use warnings;
use Test::More tests=> 10;
use File::Basename;
use lib File::Basename::dirname(__FILE__).'/../..';

use URT;

&create_tables_and_classes();

my $p1 = URT::Product->get(1);
ok(!$p1, 'Get by non-existent ID correctly returns nothing');

my $p2 = URT::Product->create(id => 1, name => 'jet pack', genius => 6, manufacturer_name => 'Lockheed Martin');
ok($p2, 'Create a new Product with the same ID');

$p1 = URT::Product->get(1);
ok($p1, 'Get with the same ID returns something, now');

is($p1->id, 1, 'ID is correct');
is($p1->name, 'jet pack', 'name is correct');
is($p1->genius, 6, 'name is correct');
is($p1->manufacturer_name, 'Lockheed Martin', 'name is correct');
 

sub create_tables_and_classes {
    my $dbh = URT::DataSource::SomeSQLite->get_default_handle;

    ok($dbh, 'Got a database handle');
 
    ok($dbh->do('create table PRODUCT
                ( prod_id int NOT NULL PRIMARY KEY, name varchar, genius integer, manufacturer_name varchar)'),
       'created product table');

    ok(UR::Object::Type->define(
            class_name => 'URT::Product',
            table_name => 'PRODUCT',
            id_by => [
                prod_id =>           { is => 'NUMBER' },
            ],
            has => [
                name =>              { is => 'STRING' },
                genius =>            { is => 'NUMBER' },
                manufacturer_name => { is => 'STRING' },
            ],
            data_source => 'URT::DataSource::SomeSQLite',
        ),
        "Created class for Product");
}

