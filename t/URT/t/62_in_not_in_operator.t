use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;

use Test::More tests => 28;
use URT::DataSource::SomeSQLite;

&setup_classes_and_db();

my(@things,%things_by_id);

@things = URT::Thing->get(value => [1,2,3]);
is(scalar(@things), 3, 'Got 3 things from the DB with IN');
%things_by_id = map { $_->value => $_ } @things;

is($things_by_id{'1'}->id, 1, 'Got value 1');
is($things_by_id{'2'}->id, 2, 'Got value 2');
is($things_by_id{'3'}->id, 3, 'Got value 3');

@things = URT::Thing->get('value not' => [1,2,3,4,5]);
is(scalar(@things), 3, 'Got 3 things from the DB with NOT IN');
%things_by_id = map { $_->value => $_ } @things;

is($things_by_id{'6'}->id, 6, 'Got value 6');
is($things_by_id{'7'}->id, 7, 'Got value 7');
is($things_by_id{'8'}->id, 8, 'Got value 8');

@things = URT::Thing->get(value => [1,2,3]);
is(scalar(@things), 3, 'Got 3 things from the cache with IN');
%things_by_id = map { $_->value => $_ } @things;

is($things_by_id{'1'}->id, 1, 'Got value 1');
is($things_by_id{'2'}->id, 2, 'Got value 2');
is($things_by_id{'3'}->id, 3, 'Got value 3');

@things = URT::Thing->get('value not' => [1,2,3,4,5]);
is(scalar(@things), 3, 'Got 3 things from the cache with NOT IN');
%things_by_id = map { $_->value => $_ } @things;

is($things_by_id{'6'}->id, 6, 'Got value 6');
is($things_by_id{'7'}->id, 7, 'Got value 7');
is($things_by_id{'8'}->id, 8, 'Got value 8');


@things = URT::Thing->get(value => [ 2,3,4 ]);
is(scalar(@things), 3, 'Got 3 things from the DB and cache with IN');
%things_by_id = map { $_->value => $_ } @things;

is($things_by_id{'4'}->id, 4, 'Got value 4');
is($things_by_id{'2'}->id, 2, 'Got value 2');
is($things_by_id{'3'}->id, 3, 'Got value 3');


@things = URT::Thing->get('value not' => [1,2,3,7,8]);
is(scalar(@things), 3, 'Got 3 things from the DB and cache with NOT IN');
%things_by_id = map { $_->value => $_ } @things;

is($things_by_id{'4'}->id, 4, 'Got value 4');
is($things_by_id{'5'}->id, 5, 'Got value 5');
is($things_by_id{'6'}->id, 6, 'Got value 6');



sub setup_classes_and_db {
    my $dbh = URT::DataSource::SomeSQLite->get_default_dbh;

    ok($dbh, 'Got DB handle');

    ok( $dbh->do("create table thing (thing_id integer, value integer)"),
        'created thing table');

    my $sth = $dbh->prepare('insert into thing values (?,?)');
    ok($sth, 'Prepared insert statement');
    foreach my $val ( 1,2,3,4,5,6,7,8 ) {
        $sth->execute($val,$val);
    }

    $sth->finish;

    ok($dbh->commit(), 'DB commit');

    UR::Object::Type->define(
        class_name => 'URT::Thing',
        id_by => 'thing_id',
        has => [ 'value' ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'thing',
    );
}
        
   


