# This test does a fork to accomplish some of its work, which means it
# behaves poorly in the debugger.  If you want to debug this test, you'll
# want two windows, one where you can run the server process, and one where
# you can run the client.  Then start the server first:
# perl this_test.t server
# It will print its processID to stdout.  Next, run the client:
# perl this_test.t <pid from server>

use strict;
use warnings;
use Test::More;

use UR;
use IO::File;

plan skip_all => "Broken with new data sources.";

UR::Object::Type->define(   # Required, otherwise the associated Ghost class doesn't get auto-created
    class_name => 'Acme',
    is => ['UR::Namespace'],
);
UR::Object::Type->define(
    class_name => 'Acme::Person',
    id_by => ['person_id'],
    has => [
        # The column_name is required here, otherwise db_saved_committed does not get updated in a commit (!?)
        person_id => { is => 'Integer', column_name => 'person_id' },
        name =>      { is => 'String', column_name => 'name' },
    ],
);

my $flag_file;  # Used to send out-of-band messages between child and parent processes
my $pid;
my $do_fork = 0;
my $last_arg = $ARGV[$#ARGV] || '';
if ($last_arg eq 'server') {
    $flag_file = "/tmp/dsproxy_flag_$$";
} elsif ($last_arg and $last_arg !~ /\D/ and kill(0, $last_arg)) {
    $flag_file = "/tmp/dsproxy_flag_$last_arg";
    $pid = $last_arg;
} else {
    $flag_file = "/tmp/dsproxy_flag_$$";
    $do_fork = 1;
}
unlink($flag_file);


if ($do_fork) {
    $pid = fork();
}

if ($pid) {
    my $cleanup_sub = sub {
        diag "Killing child pid $pid";
        kill('TERM', $pid);
        unlink($flag_file);
    };

    &client_process($flag_file);
    $cleanup_sub->();
    exit();
} else {
    &server_process($flag_file);
    exit();
}


sub client_process {
    my($flag_file) = @_;

    plan tests => 20;

    sleep 3; # Give the server a chance to get started
    my $remote_ds = &connect_to_server();
    ok($remote_ds, 'connected to the remote data source');

    my $object = Acme::Person->get(person_id => 1);
    ok($object, 'Got Acme::Person with person_id 1');
    is($object->name, $pid, 'Name attribute is correct');
    
    my @objects = Acme::Person->get();
    is(@objects, 2, 'Get with no params return 2 Acme::Person objects');

    ok($object->name($$), 'Set name attribute');
    ok(UR::Context->commit(), 'Committed change back to server');

    # Wait for the server process to see the change
    while(! -f $flag_file and ! -s $flag_file) {
        sleep(1);
    }
    # And read in what it said it changed to
    my $f = IO::File->new($flag_file);
    my $string = $f->getline();
    chomp $string;
    is($string, $$, 'Server saw the correct change');
    
    my $trans = UR::Context::Transaction->begin();
    ok($trans, 'Create a software transaction');
    ok( $object->name('abcdef'), 'Change the name property again');
    ok( ! UR::Context->commit(), 'Committing correctly failed - object is already changed');
    ok( $trans->rollback(), 'Rolling back after unsuccessful commit');
    
    my $newobj = Acme::Person->create(name => 'Bob', person_id => 2);
    ok($newobj, "Create a new person object");
    
    my $delobj = Acme::Person->get(name => 'deleteme');
    ok($delobj, 'retrieved an object we can delete...');
    ok($delobj->delete(), '... and deleted it');
    ok(UR::Context->commit(), 'Committed changes back to server');
    
    ok($object = Acme::Person->load(person_id => 1), 're-get the object we changed');
    is($object->name, $$, 'name value is correct');
    
    ok($newobj = Acme::Person->load(person_id => 2), 're-get the object we created');
    is($newobj->name, 'Bob', 'name value is correct');
    
    $delobj = Acme::Person->load(name => 'deleteme');
    ok(! $delobj, 'get() correctly returns nothing for the deleted object');
    
    return 1;
} # end client_process

sub connect_to_server {
    # Set up an alarm to kill the connection attempt
    $SIG{'ALRM'} = sub { ok(0,'Failed to connect to the remote data source'); exit;};
    alarm(5);
    my $remote_ds = UR::DataSource::RemoteCache->create(host => 'localhost',
                                                        port => 10293);
    alarm(0);

    UR::Context->get_current->set_data_sources(
        'Acme::Person' => $remote_ds,
        'Acme::Person::Ghost' => $remote_ds,  # Required, but maybe it shouldn't be?
    );

    return $remote_ds;
}


sub server_process {
    my $flag_file = shift;

    diag("server process PID is $$");

    # A couple objects the client process can load from us
    my $test_obj = Acme::Person->define(name => $$, person_id => 1);
    my $delete_obj = Acme::Person->define(name => 'deleteme', person_id => 100);

    # FIXME these are the default values.  Calling create with no args isn't working for some reason
    my $proxy = UR::Service::DataSourceProxy->create(host => '0.0.0.0', port => 10293);

    my $waiting_for_change = 1;
    my $callback = sub {
        $DB::single = 1;
        my $f = IO::File->new(">$flag_file");
        $f->print($test_obj->name,"\n");
        $f->close();
        $waiting_for_change = 0;
    };
    $test_obj->create_subscription(method => 'name', callback => $callback);
    $proxy->process_messages(undef);

    return 1;
}


