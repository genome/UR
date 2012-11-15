#!/usr/bin/env perl

use Command::Tree;

class CmdTest { is => 'Command::Tree', doc => 'test suite test command tree' };

if ($0 eq __FILE__) {
    exit Command::Shell->run(__PACKAGE__,@ARGV);
}

1;

