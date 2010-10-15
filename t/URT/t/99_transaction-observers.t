#
#===============================================================================
#
#         FILE:  99_transaction-observers.t
#
#  DESCRIPTION:  
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Nathan Nutter (nnutter@genome.wustl.edu), 
#      COMPANY:  Genome Center at Washington University
#      VERSION:  1.0
#      CREATED:  10/12/2010 02:02:21 PM
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;
use UR;
use IO::File;

use Test::More;

UR::Object::Type->define(
    class_name => 'Circle',
    has => [
        radius => {
            is => 'Number',
        },
    ],
);

sub add_test_observer {
    my ($aspect, $context, $observer_ran_ref) = @_;
    $$observer_ran_ref = 0;
    my $observer;
    $observer = $context->add_observer(
        aspect => $aspect,
        callback => sub {
            $$observer_ran_ref = 1;
            if ($observer) { 
                $observer->delete unless ($observer->isa('UR::DeletedRef'));
                undef $observer;
            }
        }
    );
    unless ($observer) {
        die "Failed to add $aspect observer!";
    }
    return 1;
}

my $o = Circle->create(radius => 1);
isa_ok($o, 'Circle');

print "Starting rollback tests...\n";
$o->radius(3);
ok($o->radius == 3, "original radius is three");
my $transaction = UR::Context::Transaction->begin();
my $observer_ran = 0;
add_test_observer('rollback', $transaction, \$observer_ran);
ok($transaction->isa('UR::Context::Transaction'), "created first transaction (to test rollback observer)");
ok(!$observer_ran, "observer rollback flag reset to 0");
$o->radius(5);
ok($o->radius == 5, "in transaction (rollback test), radius is five");
ok($transaction->rollback(), "ran transaction rollback");
ok($observer_ran, "rollback observer ran successfully");
ok($o->radius == 3, "after rollback, radius is three");

print "Starting commit tests...\n";
$o->radius(4);
ok($o->radius == 4, "original radius (commit test) is four");
$transaction = UR::Context::Transaction->begin();
add_test_observer('commit', $transaction, \$observer_ran);
ok($transaction->isa('UR::Context::Transaction'), "created second transaction (to test commit observer)");
ok(!$observer_ran, "observer rollback flag reset to 0");
$o->radius(6);
ok($o->radius == 6, "in transaction (commit test), radius is six");
ok($transaction->commit(), "ran transaction commit");
ok($observer_ran, "commit observer ran successfully");
ok($o->radius == 6, "after commit, radius is six");

print "Starting transaction within a transaction tests...\n";
$o->radius(3);
ok($o->radius == 3, "original radius is three");
my $outer_transaction = UR::Context::Transaction->begin();
my $outer_observer_ran = 0;
add_test_observer('rollback', $outer_transaction, \$outer_observer_ran);
ok($outer_transaction->isa('UR::Context::Transaction'), "created outer transaction");
ok(!$outer_observer_ran, "outer observer flag reset to 0");
$o->radius(5);
ok($o->radius == 5, "in outer transaction, radius is five");
my $inner_transaction = UR::Context::Transaction->begin();
my $inner_observer_ran = 0;
add_test_observer('rollback', $inner_transaction, \$inner_observer_ran);
ok($transaction->isa('UR::Context::Transaction'), "created inner transaction");
ok(!$inner_observer_ran, "inner observer flag reset to 0");
$o->radius(6);
ok($o->radius == 6, "in inner transaction, radius is six");
ok($inner_transaction->rollback(), "ran inner transaction rollback");
ok($inner_observer_ran, "inner transaction observer ran successfully");
ok($o->radius == 5, "after inner transaction rollback, radius is five");
ok($outer_transaction->rollback(), "ran transaction rollback");
ok($outer_observer_ran, "outer transaction observer ran successfully");
ok($o->radius == 3, "after rollback, radius is three");

# no open transactions
my $rv= eval {$transaction->rollback()} || 0;
ok($rv == 0, "properly failed transaction rollback");

done_testing();

1;
