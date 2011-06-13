use strict;
use warnings;
use Test::More tests=> 30;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

use URT;

# Tests a class that has optional hangoff data.
# query for objects, including hints for the hangoffs, and then call the
# accessor for the hangoff data.  The accessors should not trigger additional
# DB queries, even for those with missing hangoff data.

my $dbh = URT::DataSource::SomeSQLite->get_default_handle;

ok($dbh, 'Got a database handle');

ok($dbh->do('create table PERSON
            ( person_id int NOT NULL PRIMARY KEY, name varchar )'),
   'created person table');
ok($dbh->do('create table PERSON_INFO
            (pi_id int NOT NULL PRIMARY KEY, person_id integer REFERENCES person(person_id), key varchar, value varchar)'),
    'created person_info table');

$dbh->do("insert into person values (1,'Kermit')");
$dbh->do("insert into person_info values (1,1,'color', 'green')");
$dbh->do("insert into person_info values (2,1,'species','frog')");
$dbh->do("insert into person_info values (3,1,'food','flies')");

$dbh->do("insert into person values (2,'Miss Piggy')");
$dbh->do("insert into person_info values (4,2,'color','pink')");
$dbh->do("insert into person_info values (5,2,'species','pig')");
$dbh->do("insert into person_info values (6,2,'sport','karate')");

ok(UR::Object::Type->define(
    class_name => 'URT::Person',
    data_source => 'URT::DataSource::SomeSQLite',
    table_name => 'PERSON',
    id_by => [
        person_id => { is => 'NUMBER' },
    ],
    has => [
        name      => { is => 'String' },
        infos     => { is => 'URT::PersonInfo', reverse_as => 'person', is_many => 1 },
        color     => { via => 'infos', to => 'value', where => [key => 'color'] },
        species   => { via => 'infos', to => 'value', where => [key => 'species'] },
        food      => { via => 'infos', to => 'value', where => [key => 'food'], is_optional => 1 },
        sport     => { via => 'infos', to => 'value', where => [key => 'sport'], is_optional => 1 },
        
    ],
),
'Created class for main');

ok(UR::Object::Type->define(
        class_name => 'URT::PersonInfo',
        table_name => 'PERSON_INFO',
        data_source => 'URT::DataSource::SomeSQLite',
        id_by => [
            pi_id =>           { is => 'NUMBER' },
        ],
        has => [
            person => { is => 'URT::Person', id_by => 'person_id' },
            key   => { is => 'string' },
            value => { is => 'string' },
        ],
    ),
"Created class for person_info");


my $query_count = 0;
my $query_text = '';
ok(URT::DataSource::SomeSQLite->create_subscription(
                    method => 'query',
                    callback => sub {$query_text = $_[0]; $query_count++}),
    'Created a subscription for query');
my $thing;

$query_count = 0;
my $person = URT::Person->get(id => 1, -hints => ['color','species','food','sport']);
ok($person, 'Got person 1');
is($query_count, 1, 'made 1 query');

$query_count = 0;
is($person->name, 'Kermit', 'Name is Kermit');
is($query_count, 0, 'Made no queries for direct property');

$query_count = 0;
is($person->color, 'green', 'Color is green');
is($query_count, 0, 'Made no queries for indirect, hinted property');

$query_count = 0;
is($person->species, 'frog', 'species is frog');
is($query_count, 0, 'Made no queries for indirect, hinted property');

$query_count = 0;
is($person->food, 'flies', 'food is fies');
is($query_count, 0, 'Made no queries for indirect, hinted property');

$query_count = 0;
is($person->sport, undef, 'sport is undef');
is($query_count, 0, 'Made no queries for indirect, hinted property');


$query_count = 0;
$person = URT::Person->get(id => 2, -hints => ['color','sport']);
ok($person, 'Got person 2');
is($query_count, 1, 'made 1 query');

$query_count = 0;
is($person->name, 'Miss Piggy', 'Name is Miss Piggy');
is($query_count, 0, 'Made no queries for direct property');

$query_count = 0;
is($person->color, 'pink', 'Color is pink');
is($query_count, 0, 'Made no queries for indirect, hinted property');

$query_count = 0;
is($person->species, 'pig', 'species is pig');
is($query_count, 1, 'Made one query for indirect, non-hinted property');

$query_count = 0;
is($person->food, undef, 'food is undef');
is($query_count, 1, 'Made one query for indirect, non-hinted property');

$query_count = 0;
is($person->sport, 'karate', 'sport is karate');
is($query_count, 0, 'Made no queries for indirect, hinted property');


