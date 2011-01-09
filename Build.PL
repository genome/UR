#!/usr/bin/env perl

use warnings FATAL => 'all';
use strict;
use Module::Build;

Module::Build->new(
  module_name => 'UR',
  license => 'perl',
  requires => {
    # known bugs with Perl 5.6
    perl => 'v5.8.7',

    # pure Perl
    'Carp'                => '',
    'Sys::Hostname'       => '1.11',
    'File::Basename'      => '2.73',
    'Lingua::EN::Inflect' => '1.88',
    'Date::Format'        => '',
    'Data::Compare'       => '0.13',
    'Text::Diff'          => '0.35',
    'Path::Class'         => '',
    'Class::Inspector'    => '',
    'XML::Dumper'         => '',
    'XML::Generator'      => '',
    'XML::Simple'         => '',
    'version'             => '',
    
    # C
    'FreezeThaw'          => '0.43',
    'YAML'                => '',
    'DBI'                 => '1.601',
    'DBD::SQLite'         => '1.14',
    'Sub::Name'           => '0.04',
    'Sub::Install'        => '0.924',
    
    # possibly move to a web-specific 
    'Net::HTTPServer'     => '',
    'CGI::Application'    => '',
    
    #'Getopt::Complete' => [
    # we may migrate some of the Command logic here and really depend on it
    # currently it is actually not _required_ to function
    'Getopt::Complete'    => 'v0.20',
    
    #'XSLT' => [
    # this stuff is hard to install and is only used by some views
    #'XML::LibXML'         => '',
    #'XML::LibXSLT'        => '',
  },
  script_files => [ 'bin/ur' ],
  test_files => [qw|t/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t|],
  tap_harness_args => { 'jobs' =>  8 },
)->create_build_script;

# These were in Makefile.PL, but have no equivalent here yet:
#  all_from 'lib/UR.pm'
#  build_requires 'Test::More' => '0.62';

