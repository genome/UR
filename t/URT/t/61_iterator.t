#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;
use Test::More tests => 20;

my $dbh = &setup_classes_and_db();

# This tests creating an iterator and doing a regular get() 
# for the same stuff, and make sure they return the same things

# create the iterator but don't read anything from it yet
my $iter = URT::Thing->create_iterator(name => 'Bob');
ok($iter, 'Created iterator for Things named Bob');

my @objs;
while (my $o = $iter->next()) {
    is($o->name, 'Bob', 'Got an object with name Bob');
    push @objs, $o;
}
is(scalar(@objs), 2, '2 Things returned by the iterator');
is_deeply( [ map { $_->id } @objs], [2,4], 'Got the right object IDs from the iterator');

@objs = ();
$iter = URT::Thing->create_iterator(-or => [[name => 'Bob'], [name => 'Joe']]);
ok($iter, 'Created an iterator for things named Bob or Joe');

while(my $o = $iter->next()) {
    push @objs, $o;
}
is(scalar(@objs), 5, '5 things returned by the iterator');
is_deeply( [ map { $_->id } @objs], [2,4,6,8,10], 'Got the right object IDs from the iterator');


@objs = ();
$iter = URT::Thing->create_iterator(-or => [[name => 'Joe', 'id <' => 8], [name => 'Bob', 'id >' => 3]]);
ok($iter, 'Created an iterator for a more complicated OR rule');
while(my $o = $iter->next()) {
    push @objs, $o;
}
is(scalar(@objs), 2, '2 things returned by the iterator');
is_deeply( [ map { $_->id } @objs], [4,6], 'Got the right object IDs from the iterator');


@objs = ();
$iter = URT::Thing->create_iterator(-or => [[name => 'Joe', data => 'foo'],[name => 'Bob']], -order => ['-data']);
ok($iter, 'Created an iterator for an OR rule with with descending order by');
while(my $o = $iter->next()) {
    push @objs, $o;
}
is(scalar(@objs), 3, '3 things returned by the iterator');
is_deeply( [ map { $_->id } @objs], [2,6,4], 'Got the right object IDs from the iterator');


@objs = ();
$iter = URT::Thing->create_iterator(-or => [[ id => 2 ], [name => 'Bob', data => 'foo']]);
ok($iter, 'Created an iterator for an OR rule with two ways to match the same single object');
while(my $o = $iter->next()) {
    push @objs, $o;
}
is(scalar(@objs), 1, 'Got one object back from the iterstor');
is_deeply( [ map { $_->id } @objs], [2], 'Gor the right object ID from the iterator');

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
           id_by => [
                'thing_id' => { is => 'Integer' },
           ],
           has => ['name', 'data'],
           data_source => 'URT::DataSource::SomeSQLite',
           table_name => 'things'),
       'Created class URT::Thing');

    return $dbh;
}
               

