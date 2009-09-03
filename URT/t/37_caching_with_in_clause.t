#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 43;

use above 'URT'; # dummy namespace

# Turn this on for debugging
#$ENV{UR_DBI_MONITOR_SQL}=1;

my $dbh = URT::DataSource::SomeSQLite->get_default_dbh;
ok($dbh, "got a db handle");
&create_db_tables($dbh);

my $load_count = 0;
ok(URT::Parent->create_subscription(
                    method => 'load',
                    callback => sub {$load_count++}),
     'Created a subscription for load');

my $query_count = 0;
my $query_text = '';
ok(URT::DataSource::SomeSQLite->create_subscription(
                    method => 'query',
                    callback => sub {$query_text = $_[0]; $query_count++}),
    'Created a subscription for query');

$load_count = 0;
$query_count = 0;
my @o = URT::Parent->get(name => [1,2,3,4,5]);
is(scalar(@o), 5, 'get() returned the correct number of items with an in clause');
is($load_count, 5, 'loaded 5 objects');
is($query_count, 1, '1 query was generated');

$load_count = 0;
$query_count = 0;
@o = URT::Parent->get(name => [1,2,3,4,5]);
is(scalar(@o), 5, 'get() returned the correct number of items with the same in clause');
is($load_count, 0, 'loaded 0 new objects');
is($query_count, 0, 'no query was generated');

$load_count = 0;
$query_count = 0;
@o = URT::Parent->get(name => [2,3,4]);
is(scalar(@o), 3, 'get() returned the correct number of items with a subset in clause');
is($load_count, 0, 'loaded 0 new objects');
#is($query_count, 0, 'no query was generated (known broken)');

foreach my $id ( 1 .. 5 ) {
    $load_count = 0;
    $query_count = 0;
    @o = URT::Parent->get(name => $id);
    is(scalar(@o), 1, 'get() returned 1 item with a single id');
    is($load_count, 0, 'no new objects were loaded');
    is($query_count, 0, 'no new queries were done');
}

$load_count = 0;
$query_count = 0;
# Note that it's probably not worth it for the query system to remove 4 and 5 
# before it constructs the SQL query
@o = URT::Parent->get(name => [4,5,6,7]);
is(scalar(@o), 4, 'get() returned the correct number of items with another in clause');
is($load_count, 2, '2 new objects were loaded');
is($query_count, 1, '1 new query was done');
# FIXME - subscriptions for 'query' doesn't pass along the SQL to the callback
#ok($query_text !~ m/4,5,6,7/, q(Generated query does not mention "('4','5','6','7')"));
#ok($query_text =~ m/6,7/, q(Generated query does mention "('6','7')"));


unlink(URT::DataSource::SomeSQLite->server);  # Remove the DB file from /tmp/


sub create_db_tables {
    my $dbh = shift;

    ok($dbh->do('create table PARENT_TABLE
                ( parent_id int NOT NULL PRIMARY KEY, name varchar)'),
       'created parent table');

    ok(UR::Object::Type->define( 
            class_name => 'URT::Parent',
            type_name => 'parent',
            table_name => 'PARENT_TABLE',
            id_by => [
                'parent_id' =>     { is => 'NUMBER' },
            ],
            has => [
                'name' =>          { is => 'STRING' },
            ],
            data_source => 'URT::DataSource::SomeSQLite',
        ),
        "Created class for Parent");

    my $sth = $dbh->prepare('insert into parent_table (parent_id, name) values (?,?)');
    ok($sth,'insert statement prepared');
    foreach my $n ( 1 .. 10 ) {
        ok($sth->execute($n,$n), "inserted parent ID $n");
    }
}


