#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;
use Test::More tests => 14;

&setup_classes_and_db();

# This tests creating an iterator and doing a regular get() 
# for the same stuff, and make sure they return the same things

# create the iterator but don't read anything from it yet
my $iter = URT::Thing->create_iterator(name => 'Bob');
ok($iter, 'Created iterator for Things named Bob');

my $o = URT::Thing->get(thing_id => 2);

my @objs = URT::Thing->get(name => 'Bob');

is(scalar(@objs), 2, 'Get returned 2 objects');

my @objs_iter;
while (my $obj = $iter->next()) {
    push @objs_iter, $obj;
}

is(scalar(@objs_iter), 2, 'The iterator returned 2 objects');

is_deeply(\@objs_iter, \@objs, 'Iterator and get() returned the same things');


# Iterators should return things that matched at the time the iterator was
# created.  First the iterator asks for things named Joe.  Later, one of those
# objects has its name changed so it no longer matches, and another object
# is delete.  The iterator should return all 3 objects even though 2 no
# longer match

$iter = URT::Thing->create_iterator(name => 'Joe');
ok($iter, 'Created iterator for Things named Joe');

$o = URT::Thing->get(thing_id => 6);
$o->name('Fred');  # Change the name so it no longer matches the request

$o = URT::Thing->get(thing_id => 10);
$o->delete();      # Delete this one

@objs = URT::Thing->get(name => 'Joe');
is(scalar(@objs), 1, 'get() returned 1 thing named Joe after changing the other');

$o = $iter->next();
is($o->id, 6, 'The first object from iterator is id 6');
is($o->name, 'Fred', 'First object name is Fred');

$o = eval { $iter->next() };
like($@, 
     qr(Attempt to fetch an object which matched.*'thing_id' => '10')s,
     'Caught exception about deleted object');

$o = $iter->next();
is($o->id, 8, 'Second object from iterator is id 8');
is($o->name, 'Joe', 'Second object name is Joe');


# Remove the test DB
unlink(URT::DataSource::SomeSQLite->server);


sub setup_classes_and_db {
    my $dbh = URT::DataSource::SomeSQLite->get_default_handle();

    ok($dbh, 'got DB handle');

    ok($dbh->do('create table things (thing_id integer, name varchar, data varchar)'),
       'Created things table');

    my $insert = $dbh->prepare('insert into things (thing_id, name, data) values (?,?,?)');
    foreach my $row ( ( [2, 'Bob', 'foo'],
                        [4, 'Bob', 'baz'],
                        [6, 'Joe', 'foo'], 
                        [8, 'Joe', 'bar'],
                        [10, 'Joe','baz'],
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
               

