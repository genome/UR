#!/usr/bin/env perl
use strict;
use warnings;
use IO::Socket;
use Data::Dumper;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

use Test::More tests => 828;

use UR::Namespace::Command::Old::DiffRewrite;

my $c = "UR::Namespace::Command::Old::DiffRewrite";

# The messaging methods print to the filehandle $Command::stderr, which defaults
# to STDERR.  Redefine it so the messages are printed to a filehandle we
# can read from, $stderr_twin, but regular perl diagnostic messages still go
# to the real STDERR
my $stderr_twin;
$UR::ModuleBase::stderr = undef;
socketpair($UR::ModuleBase::stderr,$stderr_twin, AF_UNIX, SOCK_STREAM, PF_UNSPEC);
$UR::ModuleBase::stderr->autoflush(1);
$stderr_twin->blocking(0);

my $buffer;
for my $type (qw/error warning status/) {
    my $accessor = $type . "_message";

    my $uc_type = uc($type);
    my $msg_prefix = ($type eq "status" ? "" : "$uc_type: ");

    my $msg_source_sub = $accessor . '_source';

    for my $do_queue ([],[0],[1]) {
        for my $do_dump ([],[0],[1]) {

            my $dump_flag = "dump_" . $type . "_messages";
            $c->$dump_flag(@$do_dump);

            my $queue_flag = "queue_" . $type . "_messages";
            $c->$queue_flag(@$do_queue);

            my $list_accessor = $accessor . "s";

            is($c->$accessor(),         undef ,         "$type starts unset");
            $buffer = $stderr_twin->getline;
            is($buffer, undef, "no message");

            my $cb_register = $type . "_messages_callback";
            my $cb_msg_count = 0;
            my @cb_args;
            my $callback_sub = sub { @cb_args = @_; $cb_msg_count++;};
            ok($c->$cb_register($callback_sub), "can set callback");
            is($c->$cb_register(), $callback_sub, 'can get callback');

            my $message_line = __LINE__ + 1;    # The messaging sub will be called on the next line
            is($c->$accessor("error%d", 1), "error1",       "$type setting works");
            $buffer = $stderr_twin->getline;
            is($buffer, ($c->$dump_flag ? "${msg_prefix}error1\n" : undef), ($c->$dump_flag ?  "got message 1" : "no dump") );

            my %source_info = $c->$msg_source_sub();
            is_deeply(\%source_info,
                      { $accessor => 'error1',
                        $type.'_package' => 'main',
                        $type.'_file' => __FILE__,
                        $type.'_line' => $message_line,
                        $type.'_subroutine' => undef },   # not called from within a sub
                      "$msg_source_sub returns correct info");

            is($cb_msg_count, 1, "$type callback fired");
            is_deeply(
                \@cb_args,    [$c, "error1"],       "$type callback got correct args"
            );

            is($c->$accessor(),         "error1",       "$type returns");
            $buffer = $stderr_twin->getline;
            is($buffer, undef, "no dump");

            is($c->$accessor("error2"), "error2",       "$type resetting works");
            $buffer = $stderr_twin->getline;
            is($buffer, ($c->$dump_flag ? "${msg_prefix}error2\n" : undef), ($c->$dump_flag ?  "got message 2" : "no dump") );

            is($cb_msg_count, 2, "$type callback fired");

            is($c->$accessor(),         "error2",       "$type returns");
            is_deeply(
                \@cb_args,    [$c, "error2"],       "$type callback got correct args"
            );

            is_deeply(
                [$c->$list_accessor],
                ($c->$queue_flag ? ["error1","error2"] : []),
                ($c->$queue_flag ? "$type list is correct" : "$type list is correctly empty")
            );

            is($c->$accessor(undef),    undef ,         "undef message sent to $type");

            is($cb_msg_count, 3, "$type callback fired");

            $buffer = $stderr_twin->getline;
            is($buffer, undef, 'Setting undef message results in no output');

            is($c->$accessor(),         undef ,         "$type still has the previous message");
            is_deeply(
                \@cb_args,    [$c, undef],       "$type callback got correct args"
            );

            is_deeply(
                [$c->$list_accessor],
                ($c->$queue_flag ? ["error1","error2"] : []),
                ($c->$queue_flag ? "$type list is correct" : "$type list is correctly empty")
            );

            my $listref_accessor = $list_accessor . "_arrayref";
            my $listref = $c->$listref_accessor();
            is_deeply(
    	        $listref,
                ($c->$queue_flag ? ['error1','error2'] : []),
                "$type listref is correct"
            );

            $c->$cb_register(sub { $_[1] .= "foo"});
            $c->$accessor("altered");
            $buffer = $stderr_twin->getline();
            is($buffer, ($c->$dump_flag ? "${msg_prefix}alteredfoo\n" : undef), ($c->$dump_flag ?  "got altered message" : "no dump") );
            is_deeply(
                [$c->$list_accessor],
                ($c->$queue_flag ? ["error1","error2","alteredfoo"] : []),
                ($c->$queue_flag ? "$type list is correct" : "$type list is correctly empty")
            );

            $c->$cb_register(undef);  # Unset the callback

            is($c->$accessor(undef),    undef ,         "undef message sent to $type message");
            is($cb_msg_count, 3, "$type callback correctly didn't get fired");
            $buffer = $stderr_twin->getline();
            is($buffer, undef, 'Setting undef message results in no output');
            is_deeply(
                [$c->$list_accessor],
                ($c->$queue_flag ? ["error1","error2","alteredfoo"] : []),
                ($c->$queue_flag ? "$type list is correct" : "$type list is correctly empty")
            );

            if ($c->$queue_flag) {
                $listref->[2] = "something else";
                is_deeply(
                    [$c->$list_accessor],
                    ["error1","error2","something else"],
                    "$type list is correct after changing via the listref"
                );


                @$listref = ();
                is_deeply(
                    [$c->$list_accessor],   [],    "$type list cleared out as expected"
                );
            }
        }

    }
}

1;
