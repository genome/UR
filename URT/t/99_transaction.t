#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Data::Dumper;
use Data::Compare;

# With Purity on (which UR::Util::deep_copy does), Data::Dumper::Dumper complains when it
# encounters code refs with no way to disable the warning message.  This is an underhanded
# way of disabling it.
use Carp;
$Data::Dumper::Useperl = 1;
{ no warnings 'redefine';
  *Data::Dumper::carp = sub { 1; };
}

use URT;
use UR::Change;
use UR::Context;
use UR::Context::Transaction;
use UR::DataSource;

our @test_input = (
    ["URT::Foo" => "f1","f2"],
    ["URT::Bar" => "b1","b2"],
);

our $num_classes = scalar(@test_input);
our $num_trans = 5;
plan tests => ((($num_trans * 6) * $num_classes) + 1);

sub dump_states {
    my ($before,$after);
    use YAML;
    $DB::single = 1;
    IO::File->new(">before.yml")->print(YAML::Dump($before));
    IO::File->new(">after.yml")->print(YAML::Dump($after));    
}

###########################################

sub take_state_snapshot {
    my $state = {};
    my @classes = sort UR::Object->subclasses_loaded;
    for my $class_name (@classes) {
        next if $class_name->isa("UR::Singleton");
        my @objects = sort { $a->id cmp $b->id }
            $class_name->all_objects_loaded_unsubclassed;
        next unless @objects;
        next if $class_name eq "UR::Object::Index";
        next if $class_name eq "UR::Command::Param";
        next if $class_name =~ /UR::BoolExpr.*/;
        $state->{$class_name} = {};
        for my $object (@objects) {
            my $copy = UR::Util::deep_copy($object);
            delete $copy->{_change_count};
            delete $copy->{_request_count};
            if ($class_name->isa('UR::Object::Type')) {
                delete $copy->{get_composite_id_decomposer};
                delete $copy->{_ordered_inherited_class_names};
                delete $copy->{_all_property_type_names};
                delete $copy->{'_unique_property_sets'};
                delete $copy->{_all_id_property_names};
                delete $copy->{_id_property_sorter};
            }
            for my $key (keys %$copy) {
                if (! defined $copy->{$key}) {
                    delete $copy->{$key};
                }
                elsif (ref($copy->{$key}) eq "ARRAY") {
                    for my $value (@{ $copy->{$key} }) {
                        $value = "CODE REPLACEMENT" if ref($value) eq "CODE";
                    }
                }
                elsif (ref($copy->{$key}) eq "HASH") {
                    for my $key (keys %{ $copy->{$key} }) {
                        $copy->{$key} = "CODE REPLACEMENT"
                            if ref($copy->{$key}) eq "CODE";
                    }
                }
                elsif (ref($copy->{$key}) eq "CODE") {
                    $copy->{$key} = "CODE REPLACEMENT";
                }
            }
            $state->{$class_name}{$object->id} = $copy;
        }
    }
    return $state;
}


# These represent the state of the test, and are managed by the subs below.

my ($o0, $o1, $o2, $o3, $o4, $o5, $o6, $o7, $o8);
my ($state_initial, $state_final);
my @transactions;
my @transaction_prior_states;
my $test_obj_id;

sub clear {
    # wipe everything, reset the id for test objects

    UR::Context->rollback();
    UR::Context->clear_cache();
    ($o0, $o1, $o2, $o3, $o4, $o5, $o6, $o7, $o8) = ();
    ($state_initial, $state_final) = ();
    @transactions = ();
    @transaction_prior_states = ();

    $test_obj_id = 100;
}

sub init {
    my ($class_to_test, $property1, $property2) = @_;

    # pre-transactions: take a snapshot

    $state_initial = take_state_snapshot();

    # make some changes before starting any transactions
    # these should never be reversed

    $o0 = $class_to_test->create(id => $test_obj_id, $property1 => 'value0');

    ## t0

    push @transaction_prior_states, take_state_snapshot();
    push @transactions, UR::Context::Transaction->begin();

    $o1 = $class_to_test->create(id => ++$test_obj_id, $property1 => "value1");

    $o2 = $class_to_test->create(id => ++$test_obj_id, $property1 => "value2");

    $o3 = $class_to_test->create(id => ++$test_obj_id, $property1 => "value3");

    ## t1

    push @transaction_prior_states, take_state_snapshot();
    push @transactions, UR::Context::Transaction->begin();

    $o2->delete;

    $o3->$property1("value3changed");

    $o4 = $class_to_test->create(id => ++$test_obj_id, $property1 => "value4");

    ## t2

    push @transaction_prior_states, take_state_snapshot();
    push @transactions, UR::Context::Transaction->begin();

    # change an old unchanged
    $o4->$property1("value4changed");

    # change a different part of a changed object
    $o3->$property2("value3${property2}changed");

    #UR::Context->_sync_databases();

    # change a new object
    $o5 = $class_to_test->create(id => ++$test_obj_id, $property1 => "value5");
    $o5->$property1("value5changed");

    # change something twice
    $o6 = $class_to_test->create(id => ++$test_obj_id, $property1 => "value6");

    $o6->$property2("value6changed1");
    $o6->$property2("value6changed2");

    # make something new and then delete it in the same transactions
    $o7 = $class_to_test->create(id => ++$test_obj_id, $property1 => "value7");
    $o7->delete;

    ## t3

    push @transaction_prior_states, take_state_snapshot();
    push @transactions, UR::Context::Transaction->begin();

    # re-create deleted object
    $o8 = $class_to_test->create(id => $test_obj_id, $property1 =>
"value8recreated7");

    # delete changed object
    $o6->delete();

    ## t4

    push @transaction_prior_states, take_state_snapshot();
    push @transactions, UR::Context::Transaction->begin();

    $o8->delete();

    # post-transactions: get a final snapshot

    $state_final = take_state_snapshot();
}

sub rollback_and_verify {
    my $n = shift;
    my $msg = shift;

    my $t = $transactions[$n];
    ok($t->rollback, "rolled back transactions $n " . $msg);

    my $state_now = take_state_snapshot();
    my $state_then = $transaction_prior_states[$n];
    is_deeply($state_then, $state_now, "application state now matches pre-transaction state for $n " . $msg);

    $DB::single = 1;
    print "";
}


###########################################

# find or create each class we'll test

for my $spec (@test_input) {
    my ($class_name, @property_names) = @$spec;
    if (UR::Object::Type->get($class_name)) {
        next;
    }
    UR::Object::Type->define(
        class_name => $class_name,
        has => \@property_names
    );

    # this dynamically loads, but messes up diffs because of it.
    #$class_name->generate_support_class("Ghost");
}


# ensure that the logic in clear() really takes us back to the starting point

my $state_at_test_start = take_state_snapshot();
$DB::single = 1;
clear();
my $state_after_initial_clear = take_state_snapshot();
is_deeply($state_at_test_start, $state_after_initial_clear, "clear returns restores state with no changes");
#dump_states($state_at_test_start,$state_after_initial_clear);

# test each specified class

for my $test_class_data (@test_input) {

    my ($test_class_name, @test_property_names) = @$test_class_data;

    # test clear with this class

    init($test_class_name, @test_property_names);
    clear();
    my $state_after_first_init_and_clear_for_class = take_state_snapshot();
    is_deeply(	$state_after_first_init_and_clear_for_class,
        $state_after_initial_clear,
        "clear returns restores state after init"
    );

    init($test_class_name, @test_property_names);
    clear();
    my $state_after_second_init_and_clear_for_class = take_state_snapshot();
    is_deeply(
        $state_after_second_init_and_clear_for_class,
        $state_after_first_init_and_clear_for_class,
        "clear returns restores state after repeated init"
    );

    # ensure we really are getting a different set of state snapshots
    # this really only needs to be done once, but requires init()

    clear();
    init($test_class_name, @test_property_names);
    is(scalar(@transactions), $num_trans, "got the expected number of transactions for the test plan: $num_trans");
    is(scalar(@transaction_prior_states), $num_trans, "got the expected number of state snapshots for the test plan: $num_trans");

    # sanity check the structures against the plan

    my $matching_states_found = eval {
        for my $state_a ($state_initial, @transaction_prior_states,$state_final) {
            for my $state_b ($state_initial, @transaction_prior_states,$state_final) {
                next if $state_a == $state_b;
                if (Compare($state_a,$state_b)) {
                    return 1;
                }
            }
        }
        return 0;
    };
    ok(!$matching_states_found, "all state snapshots differ from each other");

    # ensure we get the _same_ different set each init().

    my @expected_states = @transaction_prior_states;

    clear();
    init($test_class_name, @test_property_names);
    for my $n (0 .. $#transaction_prior_states) {
        my $expected = $expected_states[$n];
        my $actual = $transaction_prior_states[$n];
        #my $match = Compare($expected,$actual);
        #print "match is $match\n";
        is_deeply($expected, $actual, "states match for snapshot $n");
    }

    # test rollback, finally

    # simple walk backward through transactions
    for (my $n = $num_trans-1; $n >= 0; $n--) {
        rollback_and_verify($n, " with later transactions already rolled-back on $test_class_name");
    }

    # ensure rolling back multiple transactions works
    #for (my $n = 0; $n <= $num_trans; $n++) {
    for (my $n = $num_trans-1; $n >= 0; $n--) {
        clear();
        init($test_class_name, @test_property_names);
        rollback_and_verify($n, " with later transactions forcibly rolled-back on $test_class_name");
    }
}

#$Id$
