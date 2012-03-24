#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

__PACKAGE__->main('UR');

sub main {
    my ($test, $module) = @_;
    use_ok($module) or exit;
    
    $test->ur_context_class_commit_triggers_observer;
    
    done_testing();
}

sub ur_context_class_commit_triggers_observer {
    my $self = shift;
    my $context = UR::Context->current;
    ok(UR::Context->commit, 'UR::Context committed');
    
    my $commit_callback_ran;
    my $commit_callback = sub {
        $commit_callback_ran = 1;
    };
    $context->add_observer(
        aspect => 'commit',
        callback => $commit_callback,
    );

    ok(UR::Context->commit, 'UR::Context committed');
    is($commit_callback_ran, 1, 'commit_callback ran');
}
