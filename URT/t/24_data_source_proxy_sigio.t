use strict;
use warnings;
use Test::More tests => 5;

use UR;

UR::Object::Type->define(
    class_name => 'Acme::Person',
    id_by => ['person_id'],
    has => ['name'],
);

my $pid;

if ($pid = fork()) {
    my @before_results = Acme::Person->get();
    ok(@before_results == 0, 'Before connecting, there are no Person objects in the cache');

    sleep 5;  # Give the child process time to get set up

    # Some cleanup code
    $SIG{'__DIE__'} = sub { diag "Killing child pid $pid"; kill 'TERM', $pid; };
    END {
        kill 'TERM', $pid if $pid;
    }


    # Set up an alarm to kill the connection attempt
    $SIG{'ALRM'} = sub { ok(0,'Failed to connect to the remote data source'); exit;};
    alarm(5);
    my $remote_ds = UR::DataSource::RemoteCache->create(host => 'localhost',
                                                        port => 10293);
    alarm(0);
    ok($remote_ds, 'connected to the remote data source');

    my $class_object = UR::Object::Type->get(class_name => 'Acme::Person');
    UR::Context->get_current->set_data_sources(
        'Acme::Person' => $remote_ds,
    );

    $SIG{'ALRM'} = sub { ok(0, 'Remote get() timed out'); exit; };
    alarm(10);
    my @after_results = Acme::Person->get();
    alarm(0);
    ok(@after_results == 1, 'Got back a single object from the remote data source');
    is($after_results[0]->name, $pid, 'The name attribute is correct');

    @after_results = Acme::Person->get(name => 1);  # there shouldn't be an item with id 1
    is(@after_results, 0, 'remote get with a non-existant name correctly returned no items');

    kill('TERM', $pid);

} else {
    # child

    my $test_obj = Acme::Person->create(name => $$);

    # FIXME these are the default values.  Calling create with no args isn't working for some reason
    my $proxy = UR::Service::DataSourceProxy->create(host => '0.0.0.0', port => 10293, use_sigio => 1);

    while(1) {
        sleep 1;
    }

    exit(0);
}

