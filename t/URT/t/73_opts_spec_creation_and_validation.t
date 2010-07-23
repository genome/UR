#!/usr/bin/env perl

use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib '/gscuser/nnutter/src/git/Getopt--Complete-for-Perl/lib/';

use UR;
use Getopt::Complete::Cache;
use Test::More;

plan tests => 2;

isnt(UR::Namespace::Command::CreateCompletionSpecFile->execute({classname=>'UR::Namespace::Command'}), 0, 'creating ur completion spec');
is(Getopt::Complete::Cache->import(class => 'UR::Namespace::Command', above => 1, comp_line => 'ur'), 1, 'loading ur completion spec');
