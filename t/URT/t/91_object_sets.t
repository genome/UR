use strict;
use warnings;
use Test::More tests=> 68;
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


$query_count = 0;
my $set = URT::Person->define_set('age <' => 20);
ok($set, 'Defined set of people younger than 20');
is($query_count, 0, 'Made no queries');

$query_count = 0;
my $count = $set->count();
is($count, 0, 'Set count is 0');
is($query_count, 1, 'Made 1 query');

$query_count = 0;
my @members = $set->members();
is(scalar(@members), 0, 'Set has no members');
is($query_count, 1, 'Made 1 query');  # the above query for count didn't actually retrieve the members

$query_count = 0;
$set = URT::Person->define_set(is_cool => 1);
ok($set, 'Defined set of cool people');
is($query_count, 0, 'Made no queries');

$query_count = 0;
$count = $set->count();
is($count, 3, '3 people are cool');
is($query_count, 1, 'Made 1 query');

$query_count = 0;
@members = $set->members();
is_deeply([ map { $_->name } @members], ['Bob','Joe','Frank'], 'Got the right members');
is($query_count, 1, 'Made one query');  # again, getting the count didn't load the members

$query_count = 0;
$set = URT::Person->define_set();
ok($set, 'Defined set of all people');
is($query_count, 0, 'Made no queries');

$query_count = 0;
my @subsets = $set->group_by('car_colors');
is(scalar(@subsets), 4, 'Partitioning all people by car_colors yields 4 subsets');
is($query_count, 4, 'Made 4 queries');  # 3 to index the car_color for the 3 owners already loaded, 1 more for the group_by car_color

# Bob and Mike have red cars, Fred and Joe have blue cars.  Frank has no car.  Bob, Joe and Frank are cool
# Bob also has a yellow car that's his primary car
my %people_by_car_color = ( 'red'    => ['Bob', 'Mike'],
                            'blue'   => ['Fred', 'Joe'],
                            'yellow' => ['Bob'],
                            ''       => ['Frank'],
                          );
foreach my $subset ( @subsets ) {
    my $query_count = 0;
    my @colors = $subset->car_colors;
    is($#colors, 0, "one color returned") or diag "@colors";
    my $color = shift @colors;
    is($query_count, 0, 'Getting car_colors from subset made no queries');

    $query_count = 0;
    @members = $subset->members();
    is($query_count, 0, 'Getting members from subset made no queries');

    my $expected_members = $people_by_car_color{$color || ''};
    is(scalar(@members), scalar(@$expected_members), 'Got the expected number of subset members');
    is_deeply([ map { $_->name } @members], $expected_members, 'Their names were correct');
}
    

$query_count = 0;
$set = URT::Person->define_set(is_cool => 0);
ok($set, 'Defined set of poeple that are not cool');
is($query_count, 0, 'Made no queries');

my %color_subsets;
my %colors = ( 'pink' => [],
               'red'  => ['Mike'],
               'blue' => ['Fred','Joe'] );
foreach my $color (keys %colors) {
    $query_count = 0;
    my $subset = $set->subset(primary_car_color => $color);
    ok($subset, "Defined a subset where primary_car_color is $color");
    is($query_count, 0, 'Made no queries');
    $color_subsets{$color} = $subset;
}

my $first_time = 1;
foreach my $color ( keys %colors ) {
    my $subset = $color_subsets{$color};
    $query_count = 0;
    my @names = $subset->name;
    my $expected_names = $colors{$color};
    is(scalar(@names), scalar(@$expected_names), "Calling 'name' on the $color subset has the right number of names");
    is_deeply(\@names, $expected_names, 'The names are correct');
    # First time through the loop, it indexes 2 car colors for primary cars
    # plus 1 query each time for getting owners for each car color
    is($query_count, $first_time ? 3 : 1, 'query count is correct');
    $first_time = 0;
}



# Test having an -order_by in addition to -group_by.  It should throw an exception if
# all the order_by columns don't appear in -group_by.

# To mix it up a bit, we'll unload the peole with yellow cars.
# This will require that it not do the sets entirely from cached objects.
for my $person (URT::Person->is_loaded(car_colors => 'yellow')) {
#    $person->unload;
}

# Now we'll delete the people with blue cars.  This means we should not get a set
# back even though the set is in the database.
#for my $person (URT::Person->is_loaded(car_colors => 'blue')) {
#    $person->delete;
#}

$query_count = 0;
@subsets = URT::Person->get(-group_by => ['car_colors'], -order_by => ['car_colors']);
is(scalar(@subsets), 4, 'Partitioning all people by car_colors yields 4 subsets, this time with order_by');
foreach (@subsets) {
    isa_ok($_, 'URT::Person::Set');
}
is_deeply([ map { $_->car_colors } @subsets ],
          [undef, 'blue', 'red', 'yellow'],
          'The color subsets were returned in the correct order');
is($query_count, 3, 'query count is correct'); # there's 2 queries for car color indexing, one more for aggregating the car colors


@subsets = eval { URT::Person->get(-group_by => ['is_cool'], -order_by => ['car_colors'])};
is(scalar(@subsets), 0, 'Partitioning all people by is_cool, order_by car_colors returned no subsets');
like($@,
   qr(^Property 'car_colors' in the -order_by list must appear in the -group_by list),
   'It threw the correct exception');

