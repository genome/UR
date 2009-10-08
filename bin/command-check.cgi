#!/usr/local/bin/perl

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
my $key = $cgi->param('key');

my $job_dir = $job_id;

print $cgi->header();

unless (-d $job_id) {
    print "Job not found!\n";
}

unless (-e "$job_id/$key") {
    print "Data value $key not found in $job_dir\n";
}

my $fh = IO::File->new("$job_dir/$key");
unless ($fh) {
    print "Failed to open file $job_dir/$key: $!";
}

while (my $line = $fh->getline) {
    print $line;
}

