#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 44;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT; # dummy namespace


my $dbh = URT::DataSource::SomeSQLite->get_default_handle;
ok($dbh, "got a handle");
isa_ok($dbh, 'UR::DBI::db', 'Returned handle is the proper class');

&setup_schema($dbh);

&test_foreign_key_handling();


sub test_foreign_key_handling {
    my $expected_fk_data = &make_expected_fk_data();

    my @table_names = qw( foo inline inline_s named named_s unnamed unnamed_s named_2 named_2_s unnamed_2 unnamed_2_s);
    foreach my $table ( @table_names ) {
        my $found = &get_fk_info_from_dd('','',$table);
        my $found_count = scalar(@$found);

        my $expected = $expected_fk_data->{'from'}->{$table};
        my $expected_count = scalar(@$expected);

        is($found_count, $expected_count, "Number of FK rows from $table is correct");
        is_deeply($found, $expected, 'FK data is correct');
    }

    foreach my $table ( @table_names ) {
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

    ok( $dbh->do('CREATE TABLE foo (id1 integer, id2 integer, PRIMARY KEY (id1, id2))'),
        'create table (foo) with 2 primary keys');

    ok($dbh->do('CREATE TABLE inline (id integer PRIMARY KEY REFERENCES foo(id1), name varchar)'),
       'create table with one inline foreign key to foo');

    ok($dbh->do('CREATE TABLE inline_s (id integer PRIMARY KEY REFERENCES foo (id1) , name varchar)'),
      'create table with one inline foreign key to foo, with different whitespace');

    ok($dbh->do('CREATE TABLE named (id integer PRIMARY KEY, name varchar, CONSTRAINT named_fk FOREIGN KEY (id) REFERENCES foo (id1))'),
       'create table with one named table constraint foreign key to foo');

    ok($dbh->do('CREATE TABLE named_s (id integer PRIMARY KEY, name varchar, CONSTRAINT named_s_fk FOREIGN KEY(id) REFERENCES foo (id1))'),
       'create table with one named table constraint foreign key to foo, with different whitespace');

    ok($dbh->do('CREATE TABLE unnamed (id integer PRIMARY KEY, name varchar, FOREIGN KEY (id) REFERENCES foo (id1))'),
       'create table with one unnamed table constraint foreign key to foo');

    ok($dbh->do('CREATE TABLE unnamed_s (id integer PRIMARY KEY, name varchar, FOREIGN KEY(id) REFERENCES foo(id1))'),
        'create table with one unnamed table constraint foreign key to foo, with different whitespace');

    ok($dbh->do('CREATE TABLE named_2 (id1 integer, id2 integer, name varchar, PRIMARY KEY (id1, id2), CONSTRAINT named_2_fk FOREIGN KEY (id1, id2) REFERENCES foo (id1,id2))'),
       'create table with a dual column named foreign key to foo');

    ok($dbh->do('CREATE TABLE named_2_s (id1 integer, id2 integer, name varchar, PRIMARY KEY ( id1 , id2 ) , CONSTRAINT named_2_s_fk FOREIGN KEY( id1 , id2 ) REFERENCES foo( id1 , id2 ) )'),
      'create table with a dual column named foreign key to foo, with different whitespace');

    ok($dbh->do('CREATE TABLE unnamed_2 (id1 integer, id2 integer, name varchar, PRIMARY KEY (id1, id2), FOREIGN KEY (id1, id2) REFERENCES foo (id1,id2))'),
       'create table with a dual column unnamed foreign key to foo');

    ok($dbh->do('CREATE TABLE unnamed_2_s (id1 integer, id2 integer, name varchar, PRIMARY KEY( id2 , id2 ) , FOREIGN KEY( id1 , id2 ) REFERENCES foo( id1 , id2 ) )'),
        'create table with a dual column unnamed foreign key to foo, with different whitespace');
}
    

sub make_expected_fk_data {
     my $from = {
             foo => [],
             inline => [
                      { FK_NAME => 'inline_id_foo_id1_fk',
                        FK_TABLE_NAME => 'inline',
                        FK_COLUMN_NAME => 'id',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'id1'
                      },
                    ],
             inline_s => [
                     { FK_NAME => 'inline_s_id_foo_id1_fk',
                        FK_TABLE_NAME => 'inline_s',
                        FK_COLUMN_NAME => 'id',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'id1'
                      },
                    ],
             named => [ 
                      { FK_NAME => 'named_fk',
                        FK_TABLE_NAME => 'named',
                        FK_COLUMN_NAME => 'id',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'id1'
                       },
                    ],
             named_s => [
                      { FK_NAME => 'named_s_fk',
                        FK_TABLE_NAME => 'named_s',
                        FK_COLUMN_NAME => 'id',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'id1'
                       },
                    ],
             unnamed => [
                      { FK_NAME => 'unnamed_id_foo_id1_fk',
                        FK_TABLE_NAME => 'unnamed',
                        FK_COLUMN_NAME => 'id',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'id1'
                       },
                    ],
             unnamed_s => [
                      { FK_NAME => 'unnamed_s_id_foo_id1_fk',
                        FK_TABLE_NAME => 'unnamed_s',
                        FK_COLUMN_NAME => 'id',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'id1'
                       },
                    ],
             named_2 => [
                      { FK_NAME => 'named_2_fk',
                        FK_TABLE_NAME => 'named_2',
                        FK_COLUMN_NAME => 'id1',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'id1'
                       },
                      { FK_NAME => 'named_2_fk',
                        FK_TABLE_NAME => 'named_2',
                        FK_COLUMN_NAME => 'id2',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'id2'
                       },
                     ],
             named_2_s => [
                      { FK_NAME => 'named_2_s_fk',
                        FK_TABLE_NAME => 'named_2_s',
                        FK_COLUMN_NAME => 'id1',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'id1'
                       },
                      { FK_NAME => 'named_2_s_fk',
                        FK_TABLE_NAME => 'named_2_s',
                        FK_COLUMN_NAME => 'id2',
                        UK_TABLE_NAME => 'foo',
                        UK_COLUMN_NAME => 'id2'
                       },
                     ],
             unnamed_2 => [
                       { FK_NAME => 'unnamed_2_id1_id2_foo_id1_id2_fk',
                         FK_TABLE_NAME => 'unnamed_2',
                         FK_COLUMN_NAME => 'id1',
                         UK_TABLE_NAME => 'foo',
                         UK_COLUMN_NAME => 'id1'
                        },
                       { FK_NAME => 'unnamed_2_id1_id2_foo_id1_id2_fk',
                         FK_TABLE_NAME => 'unnamed_2',
                         FK_COLUMN_NAME => 'id2',
                         UK_TABLE_NAME => 'foo',
                         UK_COLUMN_NAME => 'id2'
                        },
                      ],
             unnamed_2_s => [
                       { FK_NAME => 'unnamed_2_s_id1_id2_foo_id1_id2_fk',
                         FK_TABLE_NAME => 'unnamed_2_s',
                         FK_COLUMN_NAME => 'id1',
                         UK_TABLE_NAME => 'foo',
                         UK_COLUMN_NAME => 'id1'
                        },
                       { FK_NAME => 'unnamed_2_s_id1_id2_foo_id1_id2_fk',
                         FK_TABLE_NAME => 'unnamed_2_s',
                         FK_COLUMN_NAME => 'id2',
                         UK_TABLE_NAME => 'foo',
                         UK_COLUMN_NAME => 'id2'
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
