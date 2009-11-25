#!/usr/bin/env perl

use FindBin '$Bin';
use lib "$Bin/../lib";

# this "job status/result checker" really just lets you pick some file in the job's directory and dump it back
# http://mysite/cgi-bin/command-check.cgi?job_id=12345.ABCDE&key=stdout

use Command;
use CGI;
use IO::File;
use File::Temp;

my $cgi = CGI->new();
my $job_id = $cgi->param('job_id');

print $cgi->header();

my $job_dir = $job_id;
unless (-d $job_dir) {
    print "Job not found!\n";
    exit 1;
}

my ($pid) = ($job_id =~ /(\d+)\./);
my @pid_exists = `ps -p $pid`;
shift @pid_exists;
if (@pid_exists) {
    print "Found process $pid.  Killing...\n";
    kill $pid;
    my @pid_exists = `ps -p $pid`;
    shift @pid_exists;
    if (@pid_exists) {
        print "Failed to kill $pid! @pid_exists";
        exit 1;
    }
}

system "rm -rf $job_dir";
die "Failed to delete tree: $!" if -d $job_dir;

print "Job data removed.\n";

