
use warnings FATAL => 'all';
use strict;
use inc::Module::Install;

name     'UR';
license 'perl';
all_from 'lib/UR.pm';
install_script 'bin/ur';
perl_version '5.008';

# prereqs (ordered)
features (
    -core => [
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
    ],
    'Getopt::Complete' => [
        # we may migrate some of the Command logic here and really depend on it
        'Getopt::Complete'    => '0.17',
    ],
    'XSLT' => [
        # this stuff is hard to install and is only used by some views
        'XML::LibXML'         => '',
        'XML::LibXSLT'        => '',
    ],
);

# things the tests need
build_requires 'Test::More' => '0.62';
#build_requires 'Test::Deep' => '0.096';
#build_requires 'Test::Differences' => '0.47';
#build_requires 'Test::Exception' => '0.21';

tests('t/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t');

auto_install();
WriteAll();
