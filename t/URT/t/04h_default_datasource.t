#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 4;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT; # dummy namespace

subtest 'load iterator'=> sub {
    plan tests => 3;

    class URT::DefaultLoaderIter {
        has => [qw/nose tail/],
        data_source => 'UR::DataSource::Default',
    };

    sub URT::DefaultLoaderIter::__load__ {
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

    my $new = URT::DefaultLoaderIter->create(nose => 'long', tail => 'floppy', id => 1003);
    ok($new, 'made a new object');

    # The system will trust the db engine, but then will merge results with any objects
    # already in memory.  This means our new object matches, and even though only one
    # of the database rows match, the broken db above will return 2 more items.  Totalling 3.
    my @p1 = URT::DefaultLoaderIter->get(nose => ['long','wet']);
    is(scalar(@p1), 2, "got two objects as expected, because we re-check the query engine by default");

    # Now that the query results are cached, the bug in the db logic is hidden, and we return 
    # the full results.
    my @p2 = URT::DefaultLoaderIter->get(nose => ['long','wet']);
    is(scalar(@p2), 2, "got two objects as expected");
};

subtest 'load list' => sub {
    plan tests => 2;

    class URT::DefaultLoadList {
        has => [qw/nose tail/],
        data_source => 'UR::DataSource::Default',
    };

    sub URT::DefaultLoadList::__load__ {
        my ($class, $bx, $headers) = @_;
        # Same as the iter loader, but return a list of lists
        # representing the resultset
        $headers = ['nose','tail','id'];
        my $body = [
            ['wet','waggly', 1001],
            ['dry','perky', 1002],
        ];

        return $headers, $body;
    }

    # The system will trust the db engine, but then will merge results with any objects
    # already in memory.  This means our new object matches, and even though only one
    # of the database rows match, the broken db above will return 2 more items.  Totalling 3.
    my @p1 = URT::DefaultLoaderIter->get(nose => ['long','wet']);
    is(scalar(@p1), 2, "got two objects as expected, because we re-check the query engine by default");

    # Now that the query results are cached, the bug in the db logic is hidden, and we return 
    # the full results.
    my @p2 = URT::DefaultLoaderIter->get(nose => ['long','wet']);
    is(scalar(@p2), 2, "got two objects as expected");
};

subtest 'save' => sub {
    plan tests => 5;

    class URT::DefaultSave {
        has => [qw/nose tail/],
        data_source => 'UR::DataSource::Default',
    };

    my @saved_ids;
    *URT::DefaultSave::__save__ = sub {
        my $self = shift;
        push @saved_ids, $self->id;
    };

    my @committed_ids;
    *URT::DefaultSave::__commit__ = sub {
        my $self = shift;
        push @committed_ids, $self->id;
    };

    # fake loading objects from the data source by defining them
    my $unchanged = URT::DefaultSave->__define__(id => 1, nose => 'black', tail => 'fluffy');
    my $will_change = URT::DefaultSave->__define__(id => 2, nose => 'short', tail => 'blue');

    # Make some changes
    ok($will_change->tail('black'), 'change existing object');
    my $new_obj = URT::DefaultSave->create(id => 3, nose => 'medium', tail => 'smooth');
    ok($new_obj, 'created new object');

    ok(UR::Context->current->commit, 'commit changes');

    is_deeply([ sort @saved_ids ],
       [2, 3],
       'Proper objects were saved');

    is_deeply([ sort @committed_ids ],
       [2, 3],
       'Proper objects were committed');
};

subtest 'failure syncing' => sub {
    plan tests => 7;

    class URT::FailSync {
        data_source => 'UR::DataSource::Default',
    };

    sub URT::FailSync::__save__ {
        die "failed during save";
    };

    my $should_fail_during_rollback = 0;
    *URT::FailSync::__rollback__= sub {
        die "failed during rollback" if $should_fail_during_rollback;
        1;
    };

    my $obj = URT::FailSync->create(id => 1);
    local $@;
    ok(! eval { UR::Context->current->commit() }, 'failed in commit');

    like($@, qr/failed during save/, 'Exception message includes message from __save__');
    unlike($@, qr/failed during rollback/, 'Exception message does not include message from __commit__');

    my $error_message_during_commit;
    UR::DataSource::Default->dump_error_messages(0);
    UR::DataSource::Default->add_observer(
        aspect => 'error_message',
        once => 1,
        callback => sub {
            my($self, $aspect, $message) = @_;
            $error_message_during_commit = $message;
        },
    );
    $should_fail_during_rollback = 1;
    ok(! eval { UR::Context->current->commit() }, 'failed in commit second time');

    like($@, qr/failed during save/, 'Exception message includes message from __save__');
    like($@, qr/failed during rollback/, 'Exception message includes message from __commit__');
    like($error_message_during_commit,
         qr/Rollback failed:.*'id' => 1/s,
        'error_message() mentions the object failed rollback');
};
