#!/usr/bin/env perl

use warnings FATAL => 'all';
use strict;
use Module::Build;

my $subclass = Module::Build->subclass(
    class_name => 'UR::ModuleBuildSelf',
    code => q{
        sub ACTION_docs {
            # ensure docs get man pages and html
            my $self = shift;
            $self->depends_on('code');
            $self->depends_on('manpages', 'html');
        }

        sub man1page_name {
            # without this we have "man ur-init.pod" instead of "man ur-init"
            my ($self, $file) = @_;
            $file =~ s/.pod$//;
            return $self->SUPER::man1page_name($file);
        }
    }
);

my $build = $subclass->new(
  module_name => 'UR',
  license => 'perl',
  requires => {
    # known bugs with Perl 5.6
    perl => 'v5.8.7',

    # pure Perl
    'Class::Autouse'      => '2.0',
    'Class::AutoloadCAN'  => '0.03',
    'Clone::PP'           => '1.02',
    'Carp'                => '',
    'Sys::Hostname'       => '1.11',
    'File::Basename'      => '2.73',
    'Lingua::EN::Inflect' => '1.88',
    'Date::Format'        => '',
    'Data::Compare'       => '0.13',
    'Text::Diff'          => '0.35',
    'Path::Class'         => '',
    'Class::Inspector'    => '',
    #'XML::Dumper'         => '',
    #'XML::Generator'      => '',
    #'XML::Simple'         => '',
    'version'             => '',
    'JSON'                => '',
    'Test::Fork'          => '',

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
    'URI::Escape'         => '',
    
    #'Getopt::Complete' => [
    # we may migrate some of the Command logic here and really depend on it
    # currently it is actually not _required_ to function
    'Getopt::Complete'    => 'v0.20',
    
    #'XSLT' => [
    # this stuff is hard to install and is only used by some views
    #'XML::LibXML'         => '',
    #'XML::LibXSLT'        => '',
  },
  cpan_client => 'cpanm',
  script_files => [ 'bin/ur' ],
  test_files => [qw|t/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t|],
  bindoc_dirs => ['pod'],
  tap_harness_args => { 
      'jobs' =>  8,
      'rules' => { 
            par => [
                #{ seq => '../ext/DB_File/t/*' },
                #{ seq => '../ext/IO_Compress_Zlib/t/*' },
                #{ seq => '../lib/CPANPLUS/*' },
                #{ seq => '../lib/ExtUtils/t/*' },
                #'*'
                { seq => '../t/URT/t/42*' },
                '*'
            ]
      },
  },
);

foreach my $metadb_type ( qw(sqlite3 sqlite3n sqlite3-dump sqlite3n-dump sqlite3-schema sqlite3n-schema) ) {
    $build->add_build_element($metadb_type);
}

$build->create_build_script;


