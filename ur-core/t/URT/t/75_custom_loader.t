#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 3;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use UR;

###

package URT::SelfLoader1;
use URT;

class URT::SelfLoader1 {
    has => [qw/nose tail/],
    data_source => 'UR::DataSource::Default',
};

sub __load__ {
    my ($class, $bx, $headers) = @_;

    # for testing purposes we ignore the $bx and $headers, 
    # and return a 2-row, 3-column data set
    $headers = ['nose','tail','id'];
    my $body = [
        ['wet','waggly', 1001],
        ['dry','perky', 1002],
    ];

    my $iterator = sub { shift @$body };
    return $headers, $iterator;
}

###

package main;

my $new = URT::SelfLoader1->create(nose => 'long', tail => 'floppy', id => 1003); 
ok($new, "made a new object");

# The system will trust the db engine, but then will merge results with any objects
# already in memory.  This means our new object matches, and even though only one
# of the database rows match, the broken db above will return 2 more items.  Totalling 3.
my @p1 = URT::SelfLoader1->get(nose => ['long','wet']);
is(scalar(@p1), 2, "got two objects as expected, because we re-check the query engine by default");

# Now that the query results are cached, the bug in the db logic is hidden, and we return 
# the full results.
my @p2 = URT::SelfLoader1->get(nose => ['long','wet']);
is(scalar(@p2), 2, "got two objects as expected");

###

1;

