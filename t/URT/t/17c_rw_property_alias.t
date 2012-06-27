use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;

use Test::More tests => 25;
use URT::DataSource::SomeSQLite;

my $dbh = URT::DataSource::SomeSQLite->get_default_handle;
ok($dbh, 'Got DB handle');

ok( $dbh->do("create table car (car_id integer PRIMARY KEY, make varchar NOT NULL)"),
        'Created car table');

ok( $dbh->do("insert into car values(1, 'Ford')"),     'Insert car 1');
ok( $dbh->do("insert into car values(2, 'GM')"),       'Insert car 2');
ok( $dbh->do("insert into car values(3, 'Chrysler')"), 'Insert car 3');

ok($dbh->commit(), 'DB commit');

UR::Object::Type->define(
    class_name => 'URT::Car',
    id_by => [
        car_id => { is => 'Integer' },
    ],
    has_mutable => [
        make => { is => 'UR::Value::Text' },
        manufacturer => { is => 'String', via => '__self__', to => 'make' },
        #manufacturer => { is => 'String', via => 'make', to => '__self__' },
    ],
    data_source => 'URT::DataSource::SomeSQLite',
    table_name => 'car',
);

my $car = URT::Car->get(manufacturer => 'GM');
ok($car, 'Got car 2 filtered by manufacturer');
is($car->id, 2, 'It is the correct car');

$car = URT::Car->get(make => 'Ford');
ok($car, 'Got car 1 via "make"');

my $another_car = URT::Car->get(manufacturer => 'Ford');
ok($another_car, 'Got car 1 via "manufacturer');
is($car, $another_car, 'They are the same car');

ok($car->make('Honda'), 'Change make');
is($car->make, 'Honda', '"make" is updated');
is($car->manufacturer, 'Honda', '"manufacturer" is the same');

ok($car->manufacturer('Toyota'), 'Change manufacturer');
is($car->make, 'Toyota', '"make" is updated');
is($car->manufacturer, 'Toyota', '"manufacturer" is the same');


my $bmw_car = URT::Car->create(id => 4, make => 'BMW');
ok($bmw_car, 'Created new car with "make"');
is($bmw_car->make, 'BMW', '"make" returns correct value');
is($bmw_car->manufacturer, 'BMW', '"manufacturer" returns correct value');

my $audi_car = URT::Car->create(id => 5, manufacturer => 'Audi');
ok($audi_car, 'Created new car with "manufacturer"');
is($audi_car->make, 'Audi', '"make" returns correct value');
is($audi_car->manufacturer, 'Audi', '"manufacturer" returns correct value');

ok(UR::Context->commit(), 'Commit changes');

my $sth = $dbh->prepare('select * from car');
$sth->execute();
my $results = $sth->fetchall_hashref('car_id');
is_deeply($results,
        {   1 => { car_id => 1, make => 'Toyota' },
            2 => { car_id => 2, make => 'GM' },
            3 => { car_id => 3, make => 'Chrysler' },
            4 => { car_id => 4, make => 'BMW' },
            5 => { car_id => 5, make => 'Audi' } },
        'Data was saved to the DB properly');

