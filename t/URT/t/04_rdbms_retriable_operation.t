use strict;
use warnings;

use Test::More tests => 10;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT; # dummy namespace

use URT::FakeDBI;

# A Test datasource
# It allows errors with "retry this" to be retried
# The DBI component functions are at the bottom
    package URT::DataSource::Testing;

    class URT::DataSource::Testing {
        is => ['UR::DataSource::RDBMSRetriableOperations', 'URT::DataSource::SomeSQLite'],
        has => [ '_use_handle' ],
    };

    sub get_default_handle {
        my $self = UR::Util::object(shift);
        if (my $h = $self->_use_handle) {
            return $h;
        }
        return $self->super_can('get_default_handle')->($self,@_);
    }

    sub should_retry_operation_after_error {
        my($self, $sql, $dbi_errstr) = @_;
        return scalar($dbi_errstr =~ m/retry this/);
    }

    sub default_handle_class { 'URT::FakeDBI' }
            


# The entity we want to try saving

    package main;

    class TestThing {
        id_by => 'test_thing_id',
        data_source => 'URT::DataSource::Testing',
        table_name => 'test_thing',
    };

# Fake table/column info for TestThing's table
    UR::DataSource::RDBMS::Table->__define__(
        table_name => 'test_thing',
        owner => 'main',
        data_source => 'URT::DataSource::Testing');
    UR::DataSource::RDBMS::TableColumn->__define__(
        column_name => 'test_thing_id',
        table_name => 'test_thing',
        owner => 'main',
        data_source => 'URT::DataSource::Testing');

#
# Set up the test
# We only want 2 retries...
#
my $test_ds = TestThing->__meta__->data_source;
$test_ds->dump_error_messages(0);
$test_ds->retry_sleep_max_sec(3);

my $retry_count;
my @sleep_counts;
$test_ds->add_observer(
    aspect => 'retry',
    callback => sub {
        my($ds, $aspect, $sleep_time) = @_;
        $retry_count++;
        push @sleep_counts, $sleep_time;
    }
);
 
# Try a connection failure 
retry_test('connect_fail', sub { $test_ds->get_default_handle });
not_retry_test('connect_fail', sub { $test_ds->get_default_handle} );



my $test_dbh = URT::FakeDBI->new();
$test_ds->_use_handle($test_dbh);

       
#
# Start of the test...
#

retry_test('prepare_fail', sub { TestThing->get(1) });

not_retry_test('prepare_fail', sub { TestThing->get(2) });


sub retry_test {
    my($dbi_config, $code) = @_;

    note("Setting fake dbi config key $dbi_config");
    URT::FakeDBI->configure($dbi_config, 'we should retry this');
    $retry_count = 0;
    @sleep_counts = ();
    eval { $code->() };
    like($@, qr(Maximum database retries reached), 'Trapped "max retry" exception');
    is($retry_count, 2, 'Retried 2 times');
    is_deeply(\@sleep_counts, [1,2], 'Sleep times');
}
    

sub not_retry_test {
    my($dbi_config, $code) = @_;

    note("Setting fake dbi config key $dbi_config: not retrying");
    URT::FakeDBI->configure($dbi_config, 'fail only once');
    $retry_count = 0;
    eval { $code->() };
    like($@, qr(fail only once), 'non-retriable exception');
    is($retry_count, 0, 'Did not retry');
}

