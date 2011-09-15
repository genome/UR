use strict;
use warnings;
use Test::More tests=> 32;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

use URT;

my $dbh = URT::DataSource::SomeSQLite->get_default_handle;

ok($dbh, 'Got a database handle');

ok($dbh->do('create table thing ( thing_id integer not null primary key, name varchar )'),
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
        name => { is => 'Text' },
    ],
    data_source => 'URT::DataSource::SomeSQLite',
    table_name => 'thing',
);


for my $try (1 .. 2) {

    my @o = URT::Thing->get(-limit => 5);
    is(scalar(@o), 5, 'Got 5 things with limit');
    my $o = get_ids(@o);
    is_deeply($o, [1..5],'Got the right objects back');
    
    @o = URT::Thing->get('thing_id >' => 10, -limit => 5);
    is(scalar(@o), 5, 'Got 5 things with filter and limit');
    $o = get_ids(@o);
    is_deeply($o, [11..15], 'Got the right objects back');
    
    my $worked = eval { URT::Thing->get(-page => 4) };
    ok(!$worked, 'Trying to get things without -limit, but with -page did not work');
    like($@, qr(Can't define a BoolExpr with a -page), 'Exception message was correct');
    
    @o = URT::Thing->get('thing_id <' => 50, -limit => 2, -page => 6);
    is(scalar(@o), 2, 'Got two objects with -limit 2 and -page 6');
    $o = get_ids(@o);
    is_deeply($o, [11,12], 'Got the right objects back');
    
    
    
    my $iter = URT::Thing->create_iterator('thing_id >' => 30, -limit => 5);
    ok($iter, 'Created iterator with -limit');
    @o = ();
    while(my $o = $iter->next()) {
        push @o, $o;
    }
    is(scalar(@o), 5, 'Got 5 things with iterator');
    $o = get_ids(@o);
    is_deeply($o, [31 .. 35], 'Got the right objects back');
    
    
    $iter = URT::Thing->create_iterator('thing_id >' => 35, -limit => 3, -page => 6);
    ok($iter, 'Created iterator with -limit and -page');
    @o = ();
    while(my $o = $iter->next()) {
        push @o, $o;
    }
    is(scalar(@o), 3, 'Got 3 things with iterator');
    $o = get_ids(@o);
    is_deeply($o, [51,52,53], 'Got the right objects back');
    
    if ($try == 1) {
        @o = URT::Thing->get();  # To get everything into the cache
        ok(scalar(@o), 'Get all objects into cache and try the tests again');
    }
}





sub get_ids {
    my @list = map { $_->id} @_;
    return \@list;
}

