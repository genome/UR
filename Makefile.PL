
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
        'version'             => '0.74',
        'Carp'                => '',
        'Sys::Hostname'       => '1.11',
        'File::Basename'      => '2.73',
        'Lingua::EN::Inflect' => '1.88',
        'FreezeThaw'          => '0.43',
        'Date::Calc'          => '',
        'Date::Parse'         => '',
        'YAML'                => '',
        'Data::Compare'       => '0.13',
        'Text::Diff'          => '0.35',
        'DBI'                 => '1.601',
        'DBD::SQLite'         => '1.14',
        'Sub::Name'           => '0.04',
        'Sub::Install'        => '0.924',
    ],
    'Moose' => [
        #-tests  => [ [ 't/URT/t/00-load.t' ], <t/URT/t/*-moose-*.t> ],
        'Moose' => '0.31',
    ]
);

# things the tests need
build_requires 'Test::More' => '0.62';
build_requires 'Test::Fork' => '0.02';
#build_requires 'Test::Deep' => '0.096';
#build_requires 'Test::Differences' => '0.47';
#build_requires 'Test::Exception' => '0.21';

tests('t/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t');

auto_install();
WriteAll();
