use strict;
use warnings;
use Test::More tests=> 20;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

use URT;

my $dbh = URT::DataSource::SomeSQLite->get_default_handle;

ok($dbh, 'got a database handle');

ok($dbh->do('create table PERSON
            ( person_id int NOT NULL PRIMARY KEY, name varchar, is_cool integer, age integer )'),
   'created person table');
ok($dbh->do('create table CAR
            ( car_id int NOT NULL PRIMARY KEY, color varchar, is_primary int, owner_id integer references PERSON(person_id))'),
   'created car table');
ok($dbh->do('create table CAR_ENGINE
            (engine_id int NOT NULL PRIMARY KEY, car_id integer references CAR(car_id), size number)'),
   'created car_engine table');

ok(UR::Object::Type->define(
    class_name => 'URT::Person',
    table_name => 'PERSON',
    id_by => [
        person_id           => { is => 'Number' },
    ],
    has => [
        name                => { is => 'Text' },
        is_cool             => { is => 'Boolean' },
        age                 => { is => 'Integer' },
        cars                => { is => 'URT::Car', reverse_as => 'owner', is_many => 1, is_optional => 1 },
        primary_car         => { is => 'URT::Car', via => 'cars', to => '__self__', where => ['is_primary true' => 1], is_optional => 1 },
        car_colors          => { via => 'cars', to => 'color', is_many => 1 },
        primary_car_color   => { via => 'primary_car', to => 'color' },
    ],
    data_source => 'URT::DataSource::SomeSQLite',
),
'created class for people');

ok(UR::Object::Type->define(
        class_name => 'URT::Car',
        table_name => 'CAR',
        id_by => [
            car_id          => { is => 'Number' },
        ],
        has => [
            color           => { is => 'String' },
            is_primary      => { is => 'Boolean' },
            owner           => { is => 'URT::Person', id_by => 'owner_id' },
            engine          => { is => 'URT::Car::Engine', reverse_as => 'car', is_many => 1 },
        ],
        data_source => 'URT::DataSource::SomeSQLite',
    ),
    "created class for Car");

ok(UR::Object::Type->define(
        class_name => 'URT::Car::Engine',
        table_name => 'CAR_ENGINE',
        id_by => [
            engine_id   => { is => 'Number' },
        ],
        has => [
            size        => { is => 'Number' },
            car         => { is => 'URT::Car', id_by => 'car_id' },
        ],
        data_source => 'URT::DataSource::SomeSQLite',
    ),
    "created class for Engine");

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

$insert = $dbh->prepare('insert into car_engine values (?,?,?)');
foreach my $row ( [100, 1, 350], [ 200, 2, 400], [300, 3, 428], [400, 4, 429], [500, 5, 289] ) {
    $insert->execute(@$row);
}
$insert->finish();

my $query_count = 0;
my $query_text = '';
ok(URT::DataSource::SomeSQLite->create_subscription(
                    method => 'query',
                    callback => sub {$query_text = $_[0]; $query_count++}),
    'created a subscription for query');

$DB::single = 1;

note("***** FLATTEN AND *****");

my $bx0 = URT::Person->define_boolexpr(
    'is_cool' => 1,
    'primary_car_color' => 'red',
    'primary_car.engine.size' => 428,
);

my $bx0f = $bx0->flatten();
my $bx1 = URT::Person->define_boolexpr(
    'is_cool' => 1,
    'cars-primary_car.color' => 'red',
    'cars-primary_car.engine.size' => 428,
    'cars-primary_car?.is_primary true' => 1,
);
is($bx0f->normalize, $bx1->normalize, "flattening works correctly");

note("***** REFRAME AND *****");

my $bx1r1 = $bx1->reframe('primary_car');
my $bx2 = URT::Car->define_boolexpr(
    'owner.is_cool' => 1,
    'color' => 'red',
    'engine.size' => 428,
    'is_primary true' => 1,
);
is($bx1r1->normalize, $bx2->normalize, "reframe works for a one-step property embedding via/to/where");
my $bx1r2 = $bx1->reframe('primary_car.engine');
my $bx3 = URT::Car::Engine->define_boolexpr(
    'car.owner.is_cool' => 1,
    'car.color' => 'red',
    'size' => 428,
    'car.is_primary true' => 1,
);
is($bx1r2->normalize->id, $bx3->normalize->id, "reframe works on a two-step chain with the first embedding via/to/where");

my $bx33 = URT::Person->define_boolexpr(
    'primary_car.color' => 'red',
    'is_cool true' => 1,
);
my $bx33r = $bx33->reframe('primary_car');
my $bx33re = URT::Car->define_boolexpr(
    'color' => 'red',
    'owner.is_cool true' => 1,
    'is_primary true' => 1,
);

note("***** FLATTEN OR *****");

my $bx4 = URT::Person->define_boolexpr(
    -or => [
        ['is_cool' => 1],
        ['primary_car.color' => 'red'],
    ]
);
ok($bx4, "created an 'or' boolexpr");

my $bx4f = $bx4->flatten;
ok($bx4f, "flattened an OR bx");

my $bx4fe = URT::Person->define_boolexpr(
    -or => [
        ['is_cool' => 1],
        ['cars-primary_car.color' => 'red', 'cars-primary_car?.is_primary true' => 1],
    ]
);
ok($bx4fe, "defined what we expect for a flattned OR rule");
is($bx4f->id, $bx4fe->id, "the flattened OR rule matches expectations"); 


note("***** REFRAME OR *****");

my $bx4r = $bx4->reframe('primary_car');
ok($bx4r, "reframed OR expression");

my $bx4re = URT::Car->define_boolexpr(
    -or => [
        ['owner.is_cool' => 1],
        ['color' => 'red', 'is_primary true' => 1],
    ],
);
ok($bx4re, "created expected reframe expression");
is($bx4r->id, $bx4re->id, "reframed expression matches the expected expression");

note("***** FLATTEN WITH ORDER/GROUP *****");

my $bx5 = URT::Person->define_boolexpr(
    'is_cool true' => 1,
    'primary_car_color' => 'red',
    '-group_by' => ['is_cool','primary_car_color','name'],
    '-order_by' => ['is_cool','primary_car_color'],
);

my $bx5r = $bx5->reframe('primary_car');
my $bx5re = URT::Car->define_boolexpr(
    'owner.is_cool true' => 1,
    'color' => 'red',
    '-group_by' => ['owner.is_cool','color','owner.name'],
    '-order_by' => ['owner.is_cool','color'],
    'is_primary true' => 1,
);

is($bx5r->id, $bx5re->id, "reframe works on -order_by");
note("$bx5re\n$bx5r\n");

note("***** FLATTEN AROUND JOIN TO OPTIONAL WITH ON CLAUSE *****");

my $bx6 = URT::Person->define_boolexpr(
    is_cool => 1,
    -hints => ['primary_car']
);
my $bx6f = $bx6->flatten;

$DB::single = 1;
$ENV{UR_DBI_MONITOR_SQL} = 1;
my @p6f = URT::Person->get($bx6f);
my @p6 = URT::Person->get($bx6);
is("@p6f", "@p6", "got the same objects back after flattening around an optional relationship");
