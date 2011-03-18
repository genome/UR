use strict;
use warnings;
use Test::More tests=> 22;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

# Test getting some objects that includes -hints, and then that later get()s
# don't re-query the DB

use URT;

my $dbh = URT::DataSource::SomeSQLite->get_default_handle;

ok($dbh, 'Got a database handle');

ok($dbh->do('create table PERSON
            ( person_id int NOT NULL PRIMARY KEY, name varchar, is_cool integer, age integer )'),
   'created person table');
ok($dbh->do('create table CAR
            ( car_id int NOT NULL PRIMARY KEY, color varchar, is_primary int, owner_id integer references PERSON(person_id))'),
   'created car table');

ok(UR::Object::Type->define(
    class_name => 'URT::Person',
    table_name => 'PERSON',
    id_by => [
        person_id => { is => 'NUMBER' },
    ],
    has => [
        name              => { is => 'String' },
        is_cool           => { is => 'Boolean' },
        age               => { is => 'Integer' },
        cars              => { is => 'URT::Car', reverse_as => 'owner', is_many => 1, is_optional => 1 },
        primary_car       => { is => 'URT::Car', via => 'cars', to => '__self__', where => ['is_primary true' => 1] },
        car_colors        => { via => 'cars', to => 'color', is_many => 1 },
        primary_car_color => { via => 'primary_car', to => 'color' },
    ],
    data_source => 'URT::DataSource::SomeSQLite',
),
'Created class for people');

ok(UR::Object::Type->define(
        class_name => 'URT::Car',
        table_name => 'CAR',
        id_by => [
            car_id =>           { is => 'NUMBER' },
        ],
        has => [
            color   => { is => 'String' },
            is_primary => { is => 'Boolean' },
            owner   => { is => 'URT::Person', id_by => 'owner_id' },
        ],
        data_source => 'URT::DataSource::SomeSQLite',
    ),
    "Created class for Car");

# Insert some data
# Bob and Mike have red cars, Fred and Joe have blue cars.  Frank has no car.  Bob, Joe and Frank are cool
# Bob also has a yellow car that's his primary car
my $insert = $dbh->prepare('insert into person values (?,?,?,?)');
foreach my $row ( [ 11, 'Bob',1, 25 ], [12, 'Fred',0, 30], [13, 'Mike',0, 35],[14,'Joe',1, 40], [15,'Frank', 1, 45] ) {
    $insert->execute(@$row);
}
$insert->finish();

$insert = $dbh->prepare('insert into car values (?,?,?,?)');
foreach my $row ( [ 1,'red',0,  11], [ 2,'blue',1, 12], [3,'red',1,13],[4,'blue',1,14],[5,'yellow',1,11] ) {
    $insert->execute(@$row);
}
$insert->finish();


my $query_count = 0;
my $query_text = '';
ok(URT::DataSource::SomeSQLite->create_subscription(
                    method => 'query',
                    callback => sub {$query_text = $_[0]; $query_count++}),
    'Created a subscription for query');



# test creating/deleting/modifying objects that match extant sets
$query_count = 0;
my $set = URT::Person->define_set(is_cool => 1);
ok($set, 'Defined set of poeple that are cool');
is($query_count, 0, 'Made no queries');

$query_count = 0;
is($set->count, 3, '3 people are cool');
is($query_count, 1, 'Made one query');

my $bubba = URT::Person->create(name => 'Bubba', is_cool => 0, age => 25);
ok($bubba, 'Create a new not-cool person');

$query_count = 0;
is($set->count, 3, 'still, 3 people are cool');
# Currently, if a class has changed objects, the Set must do a get() for all
# members and manually count them, which requires a query in this case.  In the
# future this may not be nevessary
is($query_count, 1, 'Made one query');  

my $jamesbond = URT::Person->create(name => 'James Bond', is_cool => 1, age => '35');
ok($jamesbond, 'Create a new cool person');

$query_count = 0;
is($set->count, 4, 'now, 4 people are cool');
is($query_count, 0, 'Made no queries');

$query_count = 0;
ok($bubba->is_cool(1), 'Bubbba is now cool');
is($set->count, 5, 'After making Bubba cool, 5 people are cool');
is($query_count, 0, 'Made no queries');


$query_count = 0;
ok($jamesbond->delete, 'Delete James Bond');
is($set->count, 4, 'Now 4 people are cool');
is($query_count, 0, 'Made no queries');



