#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;
#use Test::More tests => 11;
use Test::More skip_all => 'Known broken, will fix soon';

$main::foobar = 0;
&setup_classes_and_db();

# There are 2 things in the DB and one newly created thing that satisfy
# the get() request.  But one of the DB items has been changed in the
# object cache, and sorts in a different order than the order returned by
# the DB query

# Change something in memory and see if it'll be honored in the results
my $o = URT::Thing->get(2);
$o->data('aaaa');

# Create a new thing 
my $new_obj= URT::Thing->create(name => 'Bobert', data => 'abc');

$main::foobar = 1;
my @o = URT::Thing->get('name like' => 'Bob%', -order => ['data']);
is(scalar(@o), 3, 'Got 3 things with name like Bob%');

is($o[0]->id, 2, 'thing_id == 2 is first in the list');  # The changed thing
is($o[0]->name, 'Bob', 'its name is Bob');
is($o[0]->data, 'aaaa', 'its data is foo');

is($o[1], $new_obj, 'Second item in the list is the newly created Thing');

is($o[2]->id, 4, 'thing_id == 4 is third in the list');
is($o[2]->name, 'Bobby', 'its name is Bobby');
is($o[2]->data, 'baz', 'its data is baz');

# Remove the test DB
unlink(URT::DataSource::SomeSQLite->server);


sub setup_classes_and_db {
    my $dbh = URT::DataSource::SomeSQLite->get_default_handle();

    ok($dbh, 'got DB handle');

    ok($dbh->do('create table things (thing_id integer, name varchar, data varchar)'),
       'Created things table');

    my $insert = $dbh->prepare('insert into things (thing_id, name, data) values (?,?,?)');
    foreach my $row ( ( [1, 'Joe', 'bar'],
                        [2, 'Bob', 'foo'],
                        [3, 'Fred', 'quux'],
                        [4, 'Bobby', 'baz'],
                    )) {
        unless ($insert->execute(@$row)) {
            die "Couldn't insert a row into 'things': $DBI::errstr";
        }
    }

    $dbh->commit();

    # Now we need to fast-forward the sequence past 4, since that's the highest ID we inserted manually
    my $sequence = URT::DataSource::SomeSQLite->_get_sequence_name_for_table_and_column('things', 'thing_id');
    die "Couldn't determine sequence for table 'things' column 'thing_id'" unless ($sequence);

    my $id = -1;
    while($id <= 4) {
        $id = URT::DataSource::SomeSQLite->_get_next_value_from_sequence($sequence);
    }

    ok(UR::Object::Type->define(
           class_name => 'URT::Thing',
           id_by => 'thing_id',
           has => ['name', 'data'],
           data_source => 'URT::DataSource::SomeSQLite',
           table_name => 'things'),
       'Created class URT::Thing');

}
               

