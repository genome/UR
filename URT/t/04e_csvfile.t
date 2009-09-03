#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 23;

use IO::File;

use URT; # dummy namespace

# FIXME - this doesn't test the SortedCsvFile internals like seeking and caching

my $filename = URT::DataSource::SomeCsvFile->server;
ok($filename, 'URT::DataSource::SomeCsvFile has a server');
unlink $filename if -f $filename;

our @data = ( [ 1, 'Bob', 'blue' ],
             [ 2, 'Fred', 'green' ],
             [ 3, 'Joe', 'red' ],
             [ 4, 'Frank', 'yellow' ],
           );

&setup($filename);


my $fh = URT::DataSource::SomeCsvFile->get_default_handle();
ok($fh, "got a handle");
isa_ok($fh, 'IO::Handle', 'Returned handle is the proper class');

my $thing = URT::Things->get(thing_name => 'Fred');
ok($thing, 'singular get() returned an object');
is($thing->id, 2, 'object id is correct');
is($thing->thing_id, 2, 'thing_id is correct');
is($thing->thing_name, 'Fred', 'thing_name is correct');
is($thing->thing_color, 'green', 'thing_color is correct');

my @things = URT::Things->get();
is(scalar(@things), scalar(@data), 'multiple get() returned the right number of objects');
for (my $i = 0; $i < @data; $i++) {
    # They should get returned in the same order, since @data is sorted
    is($things[$i]->thing_id, $data[$i]->[0], "Object $i thing_id is correct");
    is($things[$i]->thing_name, $data[$i]->[1], "Object $i thing_name is correct");
    is($things[$i]->thing_color, $data[$i]->[2], "Object $i thing_color is correct");
}


unlink URT::DataSource::SomeCsvFile->server;


sub setup {
    my $filename = shift;

    my $fh = IO::File->new($filename, '>');
    ok($fh, 'opened file for writing');

    my $delimiter = URT::DataSource::SomeCsvFile->delimiter;

    foreach my $line ( @data ) {
        $fh->print(join($delimiter, @$line),"\n");
    }
    $fh->close;

    my $c = UR::Object::Type->define(
        class_name => 'URT::Things',
        id_by => [
            thing_id => { is => 'Integer' },
        ],
        has => [
            thing_name => { is => 'String' },
            thing_color => { is => 'String' },
        ],
        table_name => 'FILE',
        data_source => 'URT::DataSource::SomeCsvFile'
    );

    ok($c, 'Created class');
}


1;
