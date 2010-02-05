use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;

use Test::More tests => 48;
use URT::DataSource::SomeSQLite;

END {
    unlink URT::DataSource::SomeSQLite->server;
}

my $dbh = &setup_classes_and_db();

# FIXME - add additional tests for subclassed get()s, too

my $thing = URT::Thing->get(1);
ok($thing, 'Got an object');
is($thing->value, 1, 'its value is 1');

my $cx = UR::Context->current();
ok($cx, 'Got the current context');

# First test.  Make no changes and reload the object 
ok($cx->reload($thing), 'Reloaded object after no changes');
ok(!scalar($thing->__changes__), 'No changes, as expected');

# Next test, Make a change to the database, no change to the object and reload
ok($dbh->do('update thing set value = 2 where thing_id = 1'), 'Updated value for thing in the DB to 2');
ok($cx->reload($thing), 'Reloaded object again');
is($thing->value, 2, 'its value is now 2');
ok(!scalar($thing->__changes__), 'No changes. as expected');

# Make a change to the DB, and the exact same change to the object
ok($dbh->do('update thing set value = 3 where thing_id = 1'), 'Updated value for thing in the DB to 3');
ok($thing->value(3), "Changed the object's value to 3");
ok($thing->__changes__, 'Before reloading, object says it has changes');
ok(eval { $cx->reload($thing) },'Reloaded object again');
is($@, '', 'No exceptions during reload');
is($thing->value, 3, 'Value is 3');
ok(! scalar($thing->__changes__), 'After reloading, object says it has no changes');


ok($dbh->do('update thing set value = 4 where thing_id = 1'), 'Updated value for thing in the DB to 4');
ok($thing->value(5), "Changed the object's value to 5");
ok(! eval { $cx->reload($thing) },'Reloading fails, as expected');
my $message = $@;
$message =~ s/\s+/ /gm;
like($message,
     qr/A change has occurred in the database for URT::Thing property value on object 1 from '3' to '4'. At the same time, this application has made a change to that value to '5'./,
     'Exception message looks correct');
is($thing->value, 5, 'Value is 5');


ok(UR::DBI->no_commit(1), 'Turned on no_commit');
ok($thing->value(6), "Changed the object's value to 6");
ok(UR::Context->commit(), 'calling commit()');
ok($dbh->do('update thing set value = 6 where thing_id = 1'), 'Updated value for thing in the DB to 6');
ok(eval { $cx->reload($thing) },'Reloading object again');
is($@, '', 'No exceptions during reload');
is($thing->value, 6, 'Value is 6');

ok(UR::DBI->no_commit(1), 'Turned on no_commit');
ok($thing->value(7), "Changed the object's value to 7");
ok(UR::Context->commit(), 'calling commit()');
ok($dbh->do('update thing set value = 7 where thing_id = 1'), 'Updated value for thing in the DB to 7');
ok($thing->value(8), 'Changed object value to 8');
ok(eval { $cx->reload($thing) },'Reloading object again');
is($@, '', 'No exceptions during reload');
is($thing->value, 7, 'Value is 7');

ok(UR::DBI->no_commit(1), 'Turned on no_commit');
ok($thing->value(9), "Changed the object's value to 9");
ok(UR::Context->commit(), 'calling commit()');
ok($dbh->do('update thing set value = 10 where thing_id = 1'), 'Updated value for thing in the DB to 10');
ok($thing->value(11), 'Changed object value to 11');
ok(! eval { $cx->reload($thing) },'Reloading fails, as expected');
$message = $@;
$message =~ s/\s+/ /gm;
like($message,
     qr/A change has occurred in the database for URT::Thing property value on object 1 from '7' to '10'. At the same time, this application has made a change to that value to '11'/,
     'Exception message looks correct');
is($thing->value, 11, 'Value is 11');






 




sub setup_classes_and_db {
    my $dbh = URT::DataSource::SomeSQLite->get_default_dbh;

    ok($dbh, 'Got DB handle');

    ok( $dbh->do("create table thing (thing_id integer PRIMARY KEY, value integer)"),
        'created thing table');

    my $sth = $dbh->prepare('insert into thing values (?,?)');
    ok($sth, 'Prepared insert statement');
    foreach my $val ( 1,2,3 ) {
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

    return $dbh;
}
        
   


