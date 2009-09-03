#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 44;

use URT; # dummy namespace


my $dbh = URT::DataSource::SomeSQLite->get_default_handle;
ok($dbh, "got a handle");
isa_ok($dbh, 'UR::DBI::db', 'Returned handle is the proper class');

&setup_schema($dbh);

&test_foreign_key_handling();


sub test_foreign_key_handling {
    my $expected_fk_data = &make_expected_fk_data();

    foreach my $table ( qw( foo bar baz baz2 blah blah2 ) ) {
        my $found = &get_fk_info_from_dd('','',$table);
        my $found_count = scalar(@$found);

        my $expected = $expected_fk_data->{'from'}->{$table};
        my $expected_count = scalar(@$expected);

        is($found_count, $expected_count, "Number of FK rows from $table is correct");
        is_deeply($found, $expected, 'FK data is correct');
    }

    foreach my $table ( qw( foo bar baz baz2 blah blah2 ) ) {
        my $found = &get_fk_info_from_dd('','','','','',$table);
        my $found_count = scalar(@$found);

        my $expected = $expected_fk_data->{'to'}->{$table};
        $expected = sort_fk_records($expected);
        my $expected_count = scalar(@$expected);

        is($found_count, $expected_count, "Number of FK rows to $table is correct");
        is_deeply($found, $expected, 'FK data is correct');
    }
}


unlink URT::DataSource::SomeSQLite->server;



sub setup_schema {
    my $dbh = shift;

    ok( $dbh->do('CREATE TABLE foo (foo_id_1 integer, foo_id_2 integer, PRIMARY KEY (foo_id_1, foo_id_2))'),
        'create table (foo) with 2 primary keys');

    ok($dbh->do('CREATE TABLE bar (bar_id integer PRIMARY KEY REFERENCES foo(foo_id_1), bar_name varchar)'),
       'create table (bar) with one inline foreign key to foo');

    ok($dbh->do('CREATE TABLE baz (baz_id integer PRIMARY KEY, baz_name varchar, CONSTRAINT baz_fk FOREIGN KEY (baz_id) REFERENCES foo (foo_id_1))'),
       'create table (baz) with one named table constraint foreign key to foo');

    ok($dbh->do('CREATE TABLE baz2 (baz_id integer PRIMARY KEY, baz_name varchar, FOREIGN KEY (baz_id) REFERENCES foo (foo_id_1))'),
       'create table (baz2) with one unnamed table constraint foreign key to foo');

    ok($dbh->do('CREATE TABLE blah (blah_id_1 integer, blah_id_2 integer, blah_name varchar, PRIMARY KEY (blah_id_1, blah_id_2), CONSTRAINT blah_fk FOREIGN KEY (blah_id_1, blah_id_2) REFERENCES foo (foo_id_1,foo_id_2))'),
       'create table (blah) with a dual column named foreign key to foo');

    ok($dbh->do('CREATE TABLE blah2 (blah_id_1 integer, blah_id_2 integer, blah_name varchar, PRIMARY KEY (blah_id_1, blah_id_2), FOREIGN KEY (blah_id_1, blah_id_2) REFERENCES foo (foo_id_1,foo_id_2))'),
       'create table (blah2) with a dual column unnamed foreign key to foo');
}
    

sub make_expected_fk_data {
     my $from = {
             foo => [],
             bar => [
                      { FK_NAME => 'bar_bar_id_foo_foo_id_1_fk',
                        FK_TABLE_NAME => 'bar',
                        FK_COLUMN_NAME => 'bar_id',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'foo_id_1'
                      },
                    ],
             baz => [ 
                      { FK_NAME => 'baz_fk',
                        FK_TABLE_NAME => 'baz',
                        FK_COLUMN_NAME => 'baz_id',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'foo_id_1'
                       },
                    ],
             baz2 => [
                      { FK_NAME => 'baz2_baz_id_foo_foo_id_1_fk',
                        FK_TABLE_NAME => 'baz2',
                        FK_COLUMN_NAME => 'baz_id',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'foo_id_1'
                       },
                    ],
             blah => [
                      { FK_NAME => 'blah_fk',
                        FK_TABLE_NAME => 'blah',
                        FK_COLUMN_NAME => 'blah_id_1',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'foo_id_1'
                       },
                      { FK_NAME => 'blah_fk',
                        FK_TABLE_NAME => 'blah',
                        FK_COLUMN_NAME => 'blah_id_2',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'foo_id_2'
                       },
                     ],
             blah2 => [
                       { FK_NAME => 'blah2_blah_id_1_blah_id_2_foo_foo_id_1_foo_id_2_fk',
                         FK_TABLE_NAME => 'blah2',
                         FK_COLUMN_NAME => 'blah_id_1',
                         UK_TABLE_NAME => 'foo',
                         UK_COLUMN_NAME => 'foo_id_1'
                        },
                       { FK_NAME => 'blah2_blah_id_1_blah_id_2_foo_foo_id_1_foo_id_2_fk',
                         FK_TABLE_NAME => 'blah2',
                         FK_COLUMN_NAME => 'blah_id_2',
                         UK_TABLE_NAME => 'foo',
                         UK_COLUMN_NAME => 'foo_id_2'
                        },
                      ],
          };

    # The 'to' data is just the inverse of 'from'
    my $to;
    foreach my $fk_list ( values %$from ) {
        foreach my $fk ( @$fk_list ) {
            my $uk_table = $fk->{'UK_TABLE_NAME'};
            $to->{$uk_table} ||= [];
            push @{$to->{$uk_table}}, $fk;

            my $fk_table = $fk->{'FK_TABLE_NAME'};
            $to->{$fk_table} ||= [];
        }
    }

    return { from => $from, to => $to };
}


sub get_fk_info_from_dd {
    my $sth = URT::DataSource::SomeSQLite->get_foreign_key_details_from_data_dictionary(@_);
    { no warnings 'uninitialized';
      ok($sth, "Got a sth to get foreign keys from '$_[2]' to '$_[5]'");
    }
    my @rows;
    while ( my $row = $sth->fetchrow_hashref() ) {
        push @rows, $row;
    }

    my $rows = sort_fk_records(\@rows);
    return $rows;
}



sub sort_fk_records {
    my($listref) = @_;

#    no warnings 'uninitialized';

    my @sorted = sort { 
                        $a->{'FK_TABLE_NAME'} cmp $b->{'FK_TABLE_NAME'}
                        ||
                        $a->{'FK_COLUMN_NAME'} cmp $b->{'FK_COLUMN_NAME'}
                        ||    
                        $a->{'UK_TABLE_NAME'} cmp $b->{'UK_TABLE_NAME'}
                        ||
                        $a->{'UK_COLUMN_NAME'} cmp $b->{'UK_COLUMN_NAME'}
                      } @$listref;
    return \@sorted;
}
