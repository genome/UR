#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../../lib";
use lib File::Basename::dirname(__FILE__)."/../../..";
use URT;
use Test::More tests => 18;

use IO::File;
use File::Temp;

# map people to their rank and serial nubmer
my %people = ( Pyle => { rank => 'Private', serial => 123 },
               Bailey => { rank => 'Private', serial => 234 },
               Snorkel => { rank => 'Sergent', serial => 345 },
               Carter => { rank => 'Sergent', serial => 456 },
               Halftrack => { rank => 'General', serial => 567 },
             );

my $dir = File::Temp::tempdir(CLEANUP => 1);
my $dir_strlen = length($dir);
ok($dir, 'Created temp dir');
while (my($name,$data) = each %people) {
    ok(_create_data_file($dir,$data->{'rank'},$name,$data->{'serial'}), "Create file for $name");
}


my $ds = UR::DataSource::Filesystem->create(
    server => $dir.'/$rank/${name}.dat',
    columns => ['serial'],
);
ok($ds, 'Created data source');

class URT::Thing {
    has => [
        name => { is => 'String' },
        rank => { is => 'String' },
        serial => { is => 'Number' },
    ],
    data_source_id => $ds->id,
};


my $bx = URT::Thing->define_boolexpr(name => 'Pyle', rank => 'Private');
ok($bx, 'Create boolexpr matching a name and rank');
my @data = UR::DataSource::Filesystem->_replace_vars_with_values_in_pathname(
               $bx,
               ${dir}.'/$rank/$name'
            );
is(scalar(@data), 1, 'property replacement yielded one pathname');
is_deeply(\@data, [ [ "${dir}/Private/Pyle", { name => 'Pyle', rank => 'Private'} ]],
          'Path resolution data is correct');

@data = UR::DataSource::Filesystem->_replace_vars_with_values_in_pathname(
               $bx,
               ${dir}.'/$rank/${name}.dat'
            );
is(scalar(@data), 1, 'property replacement yielded one pathname, with extension');
is_deeply(\@data, [ [ "${dir}/Private/Pyle.dat", { name => 'Pyle', rank => 'Private'} ]],
          'Path resolution data is correct');

$bx = URT::Thing->define_boolexpr(name => 'Pyle');
ok($bx, 'Create boolexpr with just name');
@data = UR::DataSource::Filesystem->_replace_vars_with_values_in_pathname(
               $bx,
               ${dir}.'/$rank/${name}.dat'
            );
is(scalar(@data), 1, 'property replacement yielded one pathname, with extension');
is_deeply(\@data, [ [ "${dir}/*/Pyle.dat", { name => 'Pyle', ($dir_strlen+1) => 'rank' } ]],
           'Path resolution data is correct');

1;



sub _create_data_file {
    my($dir,$rank,$name,$data) = @_;

    my $subdir = $dir . '/' . $rank;
    unless (-d $subdir) {
        mkdir $subdir || die "Can't create subdir $subdir: $!";
    }
    my $pathname = $subdir . '/' . $name . '.dat';
    my $f = IO::File->new($pathname, 'w') || die "Can't create file $pathname: $!";
    $f->print($data);
    1;
}
