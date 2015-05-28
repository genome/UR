use strict;
use warnings;
use Test::More tests=> 7;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

use URT;

my $dbh = URT::DataSource::SomeSQLite->get_default_handle;

ok($dbh, 'Got a database handle');

ok($dbh->do('create table thing ( thing_id integer not null primary key, idx integer )'),
   'created node table');

my $sth = $dbh->prepare('insert into thing values (?,?)');
foreach my $i ( 1 .. 100 ) {
    $sth->execute($i,$i);
}
ok($sth->finish, 'Insert test data into DB');

UR::Object::Type->define(
    class_name => 'URT::Thing',
    id_by => [
        'thing_id' => { is => 'Integer' },
    ],
    has => [
        idx => { is => 'Integer' },
    ],
    data_source => 'URT::DataSource::SomeSQLite',
    table_name => 'thing',
);


subtest 'get from DB' => sub {
    _main_test();
};

subtest 'get from cache' => sub {
    my @o = URT::Thing->get();  # To get everything into the cache

    _main_test();
};

sub _main_test {
    plan tests => 8;

    subtest 'get with limit' => sub {
        plan tests => 2;

        my @o = URT::Thing->get(-limit => 5);
        is(scalar(@o), 5, 'Got 5 things with limit');
        my $ids = get_ids(@o);
        is_deeply($ids, [1..5],'Got the right objects back');
    };
 
    subtest 'get with limit and filter' => sub {
        plan tests => 2;

        my @o = URT::Thing->get('thing_id >' => 10, -limit => 5);
        is(scalar(@o), 5, 'Got 5 things with filter and limit');
        my $ids = get_ids(@o);
        is_deeply($ids, [11..15], 'Got the right objects back');
    };

    subtest 'get with offset and filter' => sub {
        plan tests => 2;
        my @o = URT::Thing->get('thing_id <=' => 10, -offset => 5);
        is(scalar(@o), 5, 'Got 5 things with filter and offset');
        my $ids = get_ids(@o);
        is_deeply($ids, [6 .. 10], 'Got the right objects back');
    };
    
    subtest 'get with limit, offset and filter' => sub {
        plan tests => 2;

        my @o = URT::Thing->get('thing_id <' => 50, -limit => 2, -offset => 10);
        is(scalar(@o), 2, 'Got two objects with -limit 2 and -offset 10');
        my $ids = get_ids(@o);
        is_deeply($ids, [11,12], 'Got the right objects back');
    };
    

    subtest 'get with filter and page' => sub {
        plan tests => 2;

        my @o = URT::Thing->get('thing_id <' => 70, -page => [6,3]);
        is(scalar(@o), 3, 'Got 3 things with -page [6,3]');
        my $ids = get_ids(@o);
        is_deeply($ids, [16,17,18], 'Got the right objects back');
    };
    
    subtest 'iterator with filter and limit' => sub {
        plan tests => 3;

        my $iter = URT::Thing->create_iterator('thing_id >' => 30, -limit => 5);
        ok($iter, 'Created iterator with -limit');
        my @o = ();
        while(my $o = $iter->next()) {
            push @o, $o;
        }
        is(scalar(@o), 5, 'Got 5 things with iterator');
        my $ids = get_ids(@o);
        is_deeply($ids, [31 .. 35], 'Got the right objects back');
    };
    
    subtest 'iterator with filter, limit and offset' => sub {
        plan tests => 3;

        my $iter = URT::Thing->create_iterator('thing_id >' => 35, -limit => 3, -offset => 15);
        ok($iter, 'Created iterator with -limit and -offset');
        my @o = ();
        while(my $o = $iter->next()) {
            push @o, $o;
        }
        is(scalar(@o), 3, 'Got 3 things with iterator');
        my $ids = get_ids(@o);
        is_deeply($ids, [51,52,53], 'Got the right objects back');
    };


    subtest 'iterator with filter and page' => sub {
        plan tests => 3;

        my $iter = URT::Thing->create_iterator('thing_id >' => 70, -page => [5,2]);
        ok($iter, 'Create iterator with -page [5,2]');
        my @o = ();
        while(my $o = $iter->next()) {
            push @o, $o;
        }
        is(scalar(@o), 2,'Got 2 things with iterator');
        my $ids = get_ids(@o);
        is_deeply($ids, [79,80], 'Got the right objects back');
    };
}

subtest 'limit larger than result set' => sub {
    plan tests => 2;

    # All objects are already cached in memory at this point
    my $object_id = 5;
    my @o = URT::Thing->get(thing_id => $object_id, -limit => 10);
    is(scalar(@o), 1, 'got one object back');
    my $ids = get_ids(@o);
    is_deeply($ids, [ $object_id ], 'Got the right object back');
};

subtest 'offset larger than result set' => sub {
    plan tests => 2;

    my $warning_message;
    local $SIG{__WARN__} = sub { $warning_message = shift };

    my $expected_line = __LINE__ + 1;
    my @o = URT::Thing->get(thing_id => 5, -offset => 10);
    is(scalar(@o), 0, 'Got back no objects');

    my $file = __FILE__;
    like($warning_message,
        qr(-offset is larger than the result list at $file line $expected_line),
        'Warning message was as expected');
};

sub get_ids {
    my @list = map { $_->id} @_;
    return \@list;
}

