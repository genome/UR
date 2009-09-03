#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 44;

# FIXME - This tests the simple case of a single indirect property.
# Need to add a test for a doubly-indirect property crossing 2 data
# sources, and a test where the numeric order of things is differen
# than the alphabetic order

use above 'URT'; # dummy namespace

# Turn this on for debugging
#$ENV{UR_DBI_MONITOR_SQL}=1;


our $DB_FILE_1 = "/tmp/ur_testsuite_db1_$$.sqlite";
our $DB_FILE_2 = "/tmp/ur_testsuite_db2_$$.sqlite";
END {
    unlink($DB_FILE_1, $DB_FILE_1);
}

&create_data_sources();
&populate_databases();
&create_test_classes();


# Set up subscriptions to count queries and loads
my($db1_query_count, $primary_load_count, $db2_query_count, $related_load_count);
sub reset_counts {
    ($db1_query_count, $primary_load_count, $db2_query_count, $related_load_count) = (0,0,0,0);
}
ok(URT::Primary->create_subscription(
                    method => 'load',
                    callback => sub {$primary_load_count++}),
     'Created a subscription for URT::Primary load');
ok(URT::Related->create_subscription(
                    method => 'load',
                    callback => sub {$related_load_count++}),
     'Created a subscription for URT::Related load');
ok(URT::DataSource::SomeSQLite1->create_subscription(
                    method => 'query',
                    callback => sub {$db1_query_count++}),
    'Created a subscription for SomeSQLite1 query');
ok(URT::DataSource::SomeSQLite2->create_subscription(
                    method => 'query',
                    callback => sub {$db2_query_count++}),
    'Created a subscription for SomeSQLite2 query');


&reset_counts();
my @o = URT::Primary->get(related_value => '1');
is(scalar(@o), 1, "contained_value => 1 returns one Primary object");
is($db1_query_count, 1, "Queried db 1 one time");
is($primary_load_count, 1, "Loaded 1 Primary object");
is($db2_query_count, 1, "Queried db 2 one time");
is($related_load_count, 1, "Loaded 1 Related object");


&reset_counts();
@o = URT::Primary->get(primary_value => 'Two', related_value => '2');
is(scalar(@o), 1, "container_value => 'Two',contained_value=>2 returns one Primary object");
is($db1_query_count, 1, "Queried db 1 one time");
is($primary_load_count, 1, "Loaded 1 Primary object");
is($db2_query_count, 1, "Queried db 2 one time");
is($related_load_count, 1, "Loaded 1 Related object");



&reset_counts();
@o = URT::Primary->get(related_value => '2');
is(scalar(@o), 2, "contained_value => 2 returns two Primary objects");
is($db1_query_count, 1, "Queried db 1 one time");
is($primary_load_count, 1, "Loaded 1 Primary object");
# FIXME - This next one should really be 0, as the resulting query against db2 is exactly the same as
# the prior get() above.  The problem is that the cross-datasource join logic is
# functioning at the database level, not the object level.  So there's no good way of
# knowing that we've already done that query.
is($db2_query_count, 1, "Correctly didn't query db 2 (same as previous query)");
is($related_load_count, 0, "Correctly loaded 0 Related objects (they're cached)");




&reset_counts();
@o = URT::Primary->get(related_value => '3');
is(scalar(@o), 0, "contained_value => 3 correctly returns no Primary objects");
is($db1_query_count, 1, "Queried db 1 one time");
is($primary_load_count, 0, "correctly loaded 0 Primary objects");
# Note - it kind of doesn't make sense that we do a query against db2, and that query does 
# match one item in there.  UR doesn't go ahead and load it because the query against the
# primary DB returns no rows, so there's nothing to 'join' against, and no rows from db2's
# query are fetched
is($db2_query_count, 1, "Queried db 2 one time");
is($related_load_count, 0, "Correctly loaded 0 Related object");




&reset_counts();
@o = URT::Primary->get(related_value => '4');
is(scalar(@o), 0, "contained_value => 4 correctly returns no Primary objects");
# Note - same thing here, the primary query fetches 1 row, but doesn't successfully
# join to any rows in the secondary query, so no objects get loaded.
is($db1_query_count, 1, "Queried db 1 one time");
is($primary_load_count, 0, "correctly loaded 0 Primary objects");
is($db2_query_count, 1, "Queried db 2 one time");
is($related_load_count, 0, "correctly loaded 0 Related objects");





sub create_data_sources {
    class URT::DataSource::SomeSQLite1 {
        is => 'UR::DataSource::SQLite',
        type_name => 'urt datasource somesqlite1',
    };
    sub URT::DataSource::SomeSQLite1::server { $DB_FILE_1 };

    class URT::DataSource::SomeSQLite2 {
        is => 'UR::DataSource::SQLite',
        type_name => 'urt datasource somesqlite2',
    };
    sub URT::DataSource::SomeSQLite2::server { $DB_FILE_2 };
}


sub create_test_classes {
    ok(UR::Object::Type->define(
        class_name => 'URT::Related',
        id_by => [
            related_id => { is => 'Integer' },
        ],
        has => [
            related_value => { is => 'String' },
        ],
        data_source => 'URT::DataSource::SomeSQLite2',
        table_name => 'related',
    ), "create class URT::Related");

    ok(UR::Object::Type->define(
        class_name => 'URT::Primary',
        id_by => [
            primary_id => { is => 'Integer' },
        ],
        has => [
            primary_value  => { is => 'String' },
            related_id     => { is => 'Integer'},
            related_object => { is => 'URT::Related', id_by => 'related_id' },
            related_value  => { via => 'related_object', to => 'related_value' },
        ],
        data_source => 'URT::DataSource::SomeSQLite1',
        table_name => 'primary_table',
    ), "create class URT::Primary");
}



sub populate_databases {
    my $dbh = URT::DataSource::SomeSQLite1->get_default_dbh();
    ok($dbh, 'Got db handle for URT::DataSource::SomeSQLite1');

    ok($dbh->do("create table primary_table (primary_id integer PRIMARY KEY, primary_value varchar, related_id integer)"),
       "create primary table");
    # This one will match one item in related
    ok($dbh->do("insert into primary_table values (1, 'One', 1)"),
       "insert row 1 into primary");
    # these two things will match one in related
    ok($dbh->do("insert into primary_table values (2, 'Two', 2)"),
       "insert row 2 into primary");
    ok($dbh->do("insert into primary_table values (3, 'Three', 2)"),
       "insert row 3 into primary");
    # Nothing here matches related's 3
    # This will match nothing in related
    ok($dbh->do("insert into primary_table values (4, 'Four', 4)"),
       "insert row 4 into primary");

    ok($dbh->commit(), "Commit SomeSQLite1 DB");

    $dbh = URT::DataSource::SomeSQLite2->get_default_dbh();
    ok($dbh, 'Got db handle for URT::DataSource::SomeSQLite2');

    ok($dbh->do("create table related (related_id integer PRIMARY KEY, related_value varchar)"),
       "crate related table");
    ok($dbh->do("insert into related values (1, '1')"),
       "insert row 1 into related");
    ok($dbh->do("insert into related values (2, '2')"),
       "insert row 2 into related");
    ok($dbh->do("insert into related values (3, '3')"),
       "insert row 4 into related");

    ok($dbh->commit(), "Commit SomeSQLite2 DB");
}
    


