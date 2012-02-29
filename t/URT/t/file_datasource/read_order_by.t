#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../../lib";
use lib File::Basename::dirname(__FILE__)."/../../..";
use URT;
use Test::More tests => 23;

use IO::File;
use File::Temp;


# File data: id name score color
my @data = (
            [1, 'one',   10,'red'],
            [2, 'two',   10,'green'],
            [3, 'three', 9, 'blue'],
            [4, 'four',  9, 'black'],
            [5, 'five',  8, 'yellow'],
            [6, 'six',   8, 'white'],
            [7, 'seven', 7, 'purple'],
            [8, 'eight', 7, 'orange'],
            [9, 'nine',  6, 'pink'],
            [10, 'ten',  6, 'brown'],
          );

my $datafile = File::Temp->new();
ok($datafile, 'Created temp file for data');

my $data_source = UR::DataSource::Filesystem->create(
    path => $datafile->filename,
    delimiter => "\t",
    record_separator => "\n",
#    handle_class => 'URT::FileTracker',
    columns => ['thing_id','name','score','color'],
);
ok($data_source, 'Create filesystem data source');

ok(UR::Object::Type->define(
    class_name => 'URT::Thing',
    id_by => [
        thing_id => { is => 'Number' }
    ],
    has => [
        name  => { is => 'String' },
        score => { is => 'Integer' },
        color => { is => 'String'},
    ],
    data_source_id => $data_source->id,
),
'Defined class for things');


my @file_columns_in_order = ('id','name','score','color');
my %sorters;
foreach my $cols ( [id => 0], [name => 1], [score => 2], [color => 3] ) {
    my($key,$col) = @$cols;
    $sorters{$key} = sub { no warnings 'numeric'; $a->[$col] <=> $b->[$col] or $a->[$col] cmp $b->[$col] };
}

foreach my $sortby ( 0 .. 3 ) { # The number of columns in @data
    # sort the data by one of the columns...
    my @write_data = do { no warnings 'numeric';
                       sort { $a->[$sortby] <=> $b->[$sortby] or $a->[$sortby] cmp $b->[$sortby] } @data;
                     };
    ok(save_data_to_file($datafile, \@write_data), "Saved data sorted by column $sortby $file_columns_in_order[$sortby]");
    $data_source->sorted_columns( [ $data_source->columns->[$sortby] ] );

    URT::Thing->unload();
    my @results = map { [ @$_{@file_columns_in_order} ] } URT::Thing->get();
    my $sort_sub = $sorters{'id'};
    my @expected = sort $sort_sub @data;
    is_deeply(\@results, \@expected, 'Got all objects in default (id) sort order');


    for my $sort_prop ( 'name', 'score', 'color' ) {
        URT::Thing->unload();
        my @results = map { [ @$_{@file_columns_in_order} ] } URT::Thing->get(-order => [$sort_prop]);
        my $sort_sub = $sorters{$sort_prop};
        my @expected = sort $sort_sub @data;
        is_deeply(\@results, \@expected, "Got all objects sorted by $sort_prop in the right order");
    }
    
}

sub save_data_to_file {
    my($fh, $datalist) = @_;

    $fh->seek(0,0);
    $fh->print(map { $_ . "\n" }
               map { join("\t", @$_) }
               @$datalist);
    truncate($fh, $fh->tell());
    $fh->flush();
    return 1;
}

