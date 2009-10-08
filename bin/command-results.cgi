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

print $cgi->header();

my $job_dir = $job_id;
unless (-d $job_dir) {
    print "Job not found!\n";
    exit 1;
}

my ($pid) = ($job_id =~ /(\d+)\./);

my @files = sort glob("$job_id/*");

my $t = '';
$t = "<html>\n";
for my $file (@files) {
    my ($name) = ($file =~ /^$job_id\/(.*)/);
    my $content = join('',IO::File->new($file)->getlines);
    $t .= "<div id='results-$name'><b>$name:</b><br>\n<pre>$content</pre></div>\n";
}
$t .= "</html>\n";

print $t;
