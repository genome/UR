#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 5;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";

use Config;
diag explain \%Config;
#my $prefix = UR::Util->used_libs_perl5lib_prefix;
#diag("prefix is >>$prefix<<");
##$ENV{PERL5LIB} = $prefix . ':' . $ENV{PERL5LIB};
#$ENV{PERL5LIB} = $prefix . $ENV{PERL5LIB};

use UR;
use Command::Shell;
use CmdTest;
use CmdTest::C2;
use CmdTest::C3;

$ENV{PERL5LIB} .= ':' . File::Basename::dirname(__FILE__)."/../..";
diag("PERL5LIB is now >>$ENV{PERL5LIB}<<");

ok(CmdTest->isa('Command::Tree'), "CmdTest isa Command::Tree");

use_ok("CmdTest::C3");
my $path = $INC{"CmdTest/C3.pm"};
ok($path, "found path to test module")
    or die "cannot continue!";

my $result1 = `$path --thing=two`;
chomp $result1;
is($result1, "thing_id is 222", "specifying an object automatically specifies its indirect value");

my $result2 = `$path --thing-name=two`;
chomp $result2;
is($result2, "thing_id is 222", "specifying an indirect value automatically sets the value it is via");

