use strict;
use warnings;

use URT;

use Test::More tests => 6;
use URT::DataSource::SomeSQLite;

END {
    unlink URT::DataSource::SomeSQLite->server;
}

&setup_classes_and_db();

my $iter = URT::Thing->create_iterator(where => [ thing_value => { operator => '<', value => 15} ] );
my @objects;
for (my $i = 1; $i < 10; $i++) {
    push @objects, $iter->next();
}
is(scalar(@objects), 9, 'Loaded 9 objects through the (still open) iterator');

my @objects2 = URT::Thing->get(thing_value => { operator => '<', value => 15 } );
is(scalar(@objects2), 14, 'get() with same params loads all relevant objects from the DB');


$iter = undef;
@objects2 = URT::Thing->get(thing_value => { operator => '<', value => 15 } );
is(scalar(@objects2), 14, 'get() with same params loads all relevant objects from the DB after undeffing the iterator');




sub setup_classes_and_db {
    my $dbh = URT::DataSource::SomeSQLite->get_default_dbh;

    ok($dbh, 'Got DB handle');

    ok( $dbh->do("create table thing (thing_id integer, thing_value integer)"),
       'Created thing table');

    my $insert = $dbh->prepare("insert into thing (thing_id, thing_value) values (?,?)");
    for (my $i = 1; $i < 20; $i++) {
        unless($insert->execute($i,$i)) {
            ok(0, 'Failed in insert test data to DB');
            exit;
        }
    }
    $insert->finish;
    ok(1, 'Inserted test data to DB');
 
    UR::Object::Type->define(
        class_name => 'URT::Thing',
        id_by => 'thing_id',
        has => [
            thing_value => { is => 'Integer' },
        ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'thing',
    );
}

