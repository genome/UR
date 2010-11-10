#!/usr/bin/env perl

use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";

use UR;
use Test::More;
use File::Temp;

BEGIN {
    eval "use Getopt::Complete::Cache;";
    if ($@ =~ qr(Can't locate Getopt/Complete/Cache.pm in \@INC)) {
        plan skip_all => 'Getopt::Complete::Cache does not exist on the system';
    } else {
        plan tests => 7;  # This should match the number of keys in %tests below
        use_ok('Getopt::Complete::Cache');
    }
}

my $fh = File::Temp->new();
my $fname = $fh->filename;

# Create the file
isnt(UR::Namespace::Command::CreateCompletionSpecFile->execute({classname => 'UR::Namespace::Command', output => $fname}), 0, 'creating ur spec file in tmp');

# Try loading/parsing the file
ok(-f $fname, 'Output options file exists');
my $content = join('', $fh->getlines);
my $spec = eval $content;
is($@, '', 'eval of spec file worked');

# first look for >define, the next item in the list is subcommands for define
my $found = 0;
for (my $i = 0; $i < @$spec; $i++) {
    if ($spec->[$i] eq '>define') {
        $found = 1;
        $spec = $spec->[$i+1];
        last;
    }
}
ok($found, 'Found define top-level command data');

$found = 0;
for (my $i = 0; $i < @$spec; $i++) {
    if ($spec->[$i] eq '>namespace') {
        $found = 1;
        last;
    }
}
ok($found, 'Found define namespace command data');

# Try importing the file
is(Getopt::Complete::Cache->import(file => $fname, above => 1, comp_line => 1), 1, 'importing ur spec from tmp');
