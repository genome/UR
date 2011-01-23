#!/usr/bin/env perl

use warnings FATAL => 'all';
use strict;
use Module::Build;

my $class = Module::Build->subclass(
    class => 'UR::ModuleBuild',
    
    # the code below matches that in the real UR::ModuleBuild
    code => q{

        sub ACTION_clean {
            # FIXME: is this safe?
            use File::Path qw/rmtree/;
            rmtree "./_build";
            rmtree "./blib";
            unlink "./Build";
            unlink "./MYMETA.yml";
        }

        our $ns = 'UR';
        our $cmd_class = 'UR::Namespace::Command';
        our $cmd_executable = 'ur';

        sub ACTION_ur_docs {
            # We want to use UR to autodocument our code.  This is done
            # with module introspection and requires some namespace hackery
            # to work.  ./Build doc comes after ./Build and copies Genome.pm
            # into ./blib to fake a Genome namespace so this will work.
            use File::Copy qw/copy/;
            $ENV{ANSI_COLORS_DISABLED} = 1;
            
            eval {
                my $oldpwd = $ENV{PWD};

                unshift @INC, "$ENV{PWD}/blib/lib";

                my ($genome_src_dir) = grep { -s "$_/$ns.pm" } @INC;
                unless ($genome_src_dir) {
                die "Failed to find $ns.pm in \@INC.\n";
                }

                chdir "$ENV{PWD}/blib/lib/$ns" || die "Can't find $ns/";
                unless (-e "../$ns.pm") {
                    copy "$genome_src_dir/$ns.pm", "../$ns.pm" || die "Can't find $ns.pm";
                }

                eval "use $ns";
                $cmd_class->class();

                UR::Namespace::Command::Update::Pod->execute(
                    executable_name => $cmd_executable,
                    class_name => $cmd_class,
                );
                # We need to move back for perl install to find ./lib
                chdir $oldpwd;
            };

            die "failed to extract pod: $!: $@" if ($@);
        }

        sub ACTION_docs {
            my $self = shift;
            $self->depends_on('ur_docs');
            $self->depends_on('code');
            $self->depends_on('manpages', 'html');
        }

    }
);


my $build = $class->new(
  module_name => 'UR',
  license => 'perl',
  requires => {
    # known bugs with Perl 5.6
    perl => 'v5.8.7',

    # pure Perl
    'Class::Autouse'      => '2.0',
    'Clone::PP'           => '1.02',
    'Carp'                => '',
    'Sys::Hostname'       => '1.11',
    'File::Basename'      => '2.73',
    'Lingua::EN::Inflect' => '1.88',
    'Date::Pcalc'         => '',
    'Date::Format'        => '',
    'Data::Compare'       => '0.13',
    'Text::Diff'          => '0.35',
    'Path::Class'         => '',
    'Class::Inspector'    => '',
    'XML::Dumper'         => '',
    'XML::Generator'      => '',
    'XML::Simple'         => '',
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
  tap_harness_args => { 
      'jobs' =>  8,
      'rules' => { 
            par => [
                #{ seq => '../ext/DB_File/t/*' },
                #{ seq => '../ext/IO_Compress_Zlib/t/*' },
                #{ seq => '../lib/CPANPLUS/*' },
                #{ seq => '../lib/ExtUtils/t/*' },
                #'*'
                { seq => 't/URT/t/42*' },
                '*'
            ]
      },
  },
);

foreach my $metadb_type ( qw(sqlite3 sqlite3n sqlite3-dump sqlite3n-dump sqlite3-schema sqlite3n-schema) ) {
    $build->add_build_element($metadb_type);
}

$build->create_build_script;


