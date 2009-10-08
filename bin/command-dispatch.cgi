#!/usr/local/bin/perl

use FindBin '$Bin';
use lib "$Bin/../lib";

# dispatch any modularized operation from an HTTP request

use Command;
use CGI;
use IO::File;
use File::Temp;

my $cgi = CGI->new();
print $cgi->header();

my $params = $cgi->Vars;
my $delegate_class = $params->{'@'};
delete $params->{'@'};

# call communication about this request will be done in a directory owned by the request
# the status and results of the request will be in the directory
my $dir = File::Temp::tempdir("/tmp/command-dispatch.$$.XXXXX");

# before we fork, prepare to handle the child processes so we don't have zombies
# hate zombies
# (this code stolen shamelessly from "man perlipc" to reap the child -ss)
use POSIX ":sys_wait_h";
my %child_pid_exit_code;
sub REAPER {
    my $child;
    # If a second child dies while in the signal handler caused by the
    # first death, we won't get another signal. So must loop here else
    # we will leave the unreaped child as a zombie. And the next time
    # two children die we get another zombie. And so on.
    while (($child = waitpid(-1,WNOHANG)) > 0) {
        $child_pid_exit_code{$child} = $?;
    }
    $SIG{CHLD} = \&REAPER;  # still loathe sysV
}
$SIG{CHLD} = \&REAPER;

# fork so that the parent can return the path for results lookup, 
# and the child can get to work on the actual execution
if ($child_pid = fork()) {
    # the parent process returns the path to the directory which tracks output, error, status
    print $dir;
    exit;
}

#
# the child process continues and does the real work...
# feed results into files which can be polled by the browser, probably via ajax
#

# this updates the stage for the request
my $stage_logger = sub {
    my $fh = IO::File->new(">$dir/stage");
    select $fh; $| = 1;
    $fh->print(@_);
    select STDOUT; $| = 1;
};
$stage_logger->('initializing'); 

# duplicate handles to the old stdout/stderr
#open my $oldout, ">&STDOUT"     or die "Can’t dup STDOUT: $!";
#open my $olderr, ">&STDERR"     or die "Can't dup STDERR: $!";

# redirect stdin/stdout to go to our files
open STDOUT, ">$dir/stdout";
open STDERR, ">$dir/stderr";

# make them unbuffered
select STDERR; $| = 1;
select STDOUT; $| = 1;

# we still have the ability to print to the browser and web server log at this point...
#$oldout->print("oldout\n");
#$olderr->print("olderr\n");

# ...but we give it up and close the original stdin/stdout so we let the web client go
# this will end the browser "waiting" for a response
#$oldout->close;
#$olderr->close;

# now do the real work...
$stage_logger->('running'); 
my $rv = eval {
    eval "use $delegate_class";
    die $@ if $@;
    Command->_execute_delegate_class_with_params($delegate_class,$params);
};

# set status after execution has completed
if ($@) {
    $stage_logger->('crashed'); 
    STDERR->print($@);
    UR::Context->rollback;
}
elsif ($rv) {
    $stage_logger->('succeeded');
    UR::Context->commit;
}
else {
    $stage_logger->('failed');
    UR::Context->commit;
}

# restore stdout/stderr to their original streams
# (we'd do this if we hadn't already closed them)
#open STDOUT, ">&", $oldout;
#open STDERR, ">&", $olderr;

# because this is a forked child process doing the work, we exit.
my $exit_code = $delegate_class->exit_code_for_return_value($rv);
exit $exit_code;

