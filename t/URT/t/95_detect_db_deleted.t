use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";

use URT;
use Test::More tests => 270;

use URT::DataSource::SomeSQLite;

my $dbh = URT::DataSource::SomeSQLite->get_default_handle();
$dbh->do('create table thing (thing_id integer PRIMARY KEY, value varchar)');
my $sth = $dbh->prepare('insert into thing values (?,?)');
foreach my $id ( 1..5 ) {
    $sth->execute($id,$id);
}
$sth->finish;

UR::Object::Type->define(
    class_name => 'URT::Thing',
    id_by => 'thing_id',
    has => ['value'],
    data_source => 'URT::DataSource::SomeSQLite',
    table_name => 'thing',
);

my @things = URT::Thing->get();
is(scalar(@things), 5, 'Got all 5 things');

ok($dbh->do('delete from thing where thing_id = 3'),
   'Delete thing_id 3 from the database');

@things = UR::Context->reload('URT::Thing');
is(scalar(@things), 4, 'get() returned 4 things');



ok($dbh->do('delete from thing where thing_id = 5'),
   'Delete thing_id 5 from the database');
@things = UR::Context->reload('URT::Thing');
is(scalar(@things), 3, 'get() returned 3 things');


ok($dbh->do('delete from thing'),
   'Delete all remaining things from the database');
@things = UR::Context->reload('URT::Thing');
is(scalar(@things), 0, 'get() returned no things');

