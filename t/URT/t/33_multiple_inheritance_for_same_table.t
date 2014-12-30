use strict;
use warnings;

use Test::More tests => 12;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

use URT;

my $dbh = URT::DataSource::SomeSQLite->get_default_handle;

ok($dbh, 'Got a database handle');
ok($dbh->do('create table PERSON
            ( person_id int NOT NULL PRIMARY KEY, name varchar, subclass varchar)'),
   'created person table');


ok(UR::Object::Type->define(
    class_name => 'URT::Person',
    table_name => 'PERSON',
    is_abstract => 1,
    id_by => [
        person_id => { is => 'Number' },
    ],
    has => [
        name      => { is => 'Text' },
        subclass  => { is => 'Text' },
    ],
    subclassify_by => 'subclass',
    data_source => 'URT::DataSource::SomeSQLite',
),
'Created abstract class for people');

ok(UR::Object::Type->define(
    class_name => 'URT::Person::WithFavoriteColor',
    is => 'URT::Person',
    is_abstract => 1,
    has_transient_optional => [
        favorite_color => { is => 'Text' },
    ],
),
'Created abstract subclass for people who temporarily have favorite colors');

ok(UR::Object::Type->define(
    class_name => 'URT::Person::WithNickname',
    is => 'URT::Person',
    is_abstract => 1,
    has_transient_optional => [
        nickname => { is => 'Text' },
    ],
),
'Created abstract subclass for people who temporarily have nicknames');

ok(UR::Object::Type->define(
    class_name => 'URT::StudyParticipant',
    is => ['URT::Person::WithNickname', 'URT::Person::WithFavoriteColor'],
    has_transient_optional => [
        participant_id => { is => 'Number' },
    ],
),
'Created a class of person who is being asked their favorite color and nickname');

# Insert some data so we can query for it
my $insert = $dbh->prepare('insert into person values (?,?,?)');
foreach my $row ( [111, 'Alice', 'URT::StudyParticipant'] ) {
    $insert->execute(@$row);
}
$insert->finish();

my $class = 'URT::StudyParticipant';
can_ok($class, (qw(favorite_color nickname participant_id)));

my $got_select;
URT::DataSource::SomeSQLite->add_observer(
    aspect => 'query',
    callback => sub {
        my($ds, $aspect, $sql) = @_;
        ($got_select) = ($sql =~ m/SELECT\s+(.+)\s+FROM\s/im);
    });

my @participants = $class->get();
is(scalar(@participants), 1, 'got participants');
isa_ok($participants[0], $class);
is($participants[0]->name, 'Alice', 'got name of participant');
is($participants[0]->id, 111, 'got id of participant');
is($got_select, 'PERSON.name, PERSON.person_id, PERSON.subclass', 'SQL select clause');
