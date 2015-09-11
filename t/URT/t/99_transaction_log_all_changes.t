#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;

use_ok('UR::Context::Transaction');

subtest 'ensure log_all_changes is turned off after last transaction' => sub {
    plan tests => 10;


    is(scalar(() = UR::Context::Transaction->get()), 0, 'no transactions at start');
    is($UR::Context::Transaction::log_all_changes, 0, 'log_all_changes is disabled at start');
    my @tx = UR::Context::Transaction->begin();
    is($UR::Context::Transaction::log_all_changes, 1, 'beginning outer transaction enabled log_all_changes');
    push @tx, UR::Context::Transaction->begin();
    is($UR::Context::Transaction::log_all_changes, 1, 'beginning inner transaction leaves log_all_changes enabled');
    pop(@tx)->commit();
    is($UR::Context::Transaction::log_all_changes, 1, 'committing inner transaction leaves log_all_changes enabled');
    pop(@tx)->commit();
    is($UR::Context::Transaction::log_all_changes, 0, 'committing outer transaction disables log_all_changes');
    push @tx, UR::Context::Transaction->begin();
    is($UR::Context::Transaction::log_all_changes, 1, 'beginning a new first transaction enabled log_all_changes');
    push @tx, UR::Context::Transaction->begin();
    is($UR::Context::Transaction::log_all_changes, 1, 'beginning inner transaction leaves log_all_changes enabled');
    pop(@tx)->rollback();
    is($UR::Context::Transaction::log_all_changes, 1, 'rolling back inner transaction leaves log_all_changes enabled');
    pop(@tx)->rollback();
    is($UR::Context::Transaction::log_all_changes, 0, 'rolling back outer transaction disables log_all_changes');
};
