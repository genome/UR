#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../../lib";
use lib File::Basename::dirname(__FILE__)."/../../..";
use URT;
use Test::More tests => 36;

use IO::File;
use File::Temp;

# map people to their rank and serial nubmer
my %people = ( Pyle => { rank => 'Private', serial => 123 },
               Bailey => { rank => 'Private', serial => 234 },
               Snorkel => { rank => 'Sergent', serial => 345 },
               Carter => { rank => 'Sergent', serial => 456 },
               Halftrack => { rank => 'General', serial => 567 },
             );

my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
ok($tmpdir, 'Created temp dir');
my $tmpdir_strlen = length($tmpdir);

my $dir = $tmpdir . '/extra_dir';
ok(mkdir($dir), 'Created extra_dir within temp dir');
my $dir_strlen = length($dir);
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
        other => { is => 'String' },
        name => { is => 'String' },
        rank => { is => 'String' },
        serial => { is => 'Number' },
    ],
    data_source_id => $ds->id,
};


# First, test the low-level replacement methods for variables

# A simple one with single values for both properties
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


# Give 2 values for each property
$bx = URT::Thing->define_boolexpr(rank => ['General','Sergent'], name => ['Pyle','Washington']);
ok($bx, 'Create boolexpr matching name and rank with in-clauses');
@data = UR::DataSource::Filesystem->_replace_vars_with_values_in_pathname(
               $bx,
               ${dir}.'/$rank/$name.dat'
            );
is(scalar(@data), 4, 'Property replacement yields 4 pathnames');
@data = sort {$a->[0] cmp $b->[0]} @data;
is_deeply(\@data,
         [
           [ "${dir}/General/Pyle.dat",       { name => 'Pyle', rank => 'General' } ],
           [ "${dir}/General/Washington.dat", { name => 'Washington', rank => 'General' } ],
           [ "${dir}/Sergent/Pyle.dat",       { name => 'Pyle', rank => 'Sergent' } ],
           [ "${dir}/Sergent/Washington.dat", { name => 'Washington', rank => 'Sergent' } ],
         ],
         'Path resolution data is correct');



# This one only supplies a value for one property.  It'll have to glob the filesystem for the other value
$bx = URT::Thing->define_boolexpr(name => 'Pyle');
ok($bx, 'Create boolexpr with just name');
@data = UR::DataSource::Filesystem->_replace_vars_with_values_in_pathname(
               $bx,
               ${dir}.'/$rank/${name}.dat'
            );
is(scalar(@data), 1, 'property replacement yielded one pathname, with extension');
#print Data::Dumper::Dumper(\@data);
is_deeply(\@data,
           [ [ "${dir}/*/Pyle.dat",
               { name => 'Pyle', '.__glob_positions__' => [ [$dir_strlen+1, 'rank' ] ] }
             ]
           ],
           'Path resolution data is correct');

@data = UR::DataSource::Filesystem->_replace_glob_with_values_in_pathname(@{$data[0]});
is(scalar(@data), 3, 'Glob replacement yielded three possible pathnames');
@data = sort { $a->[0] cmp $b->[0] } @data;
is_deeply(\@data,
          [
              [ "${dir}/General/Pyle.dat", { name => 'Pyle', rank => 'General' } ],
              [ "${dir}/Private/Pyle.dat", { name => 'Pyle', rank => 'Private' } ],
              [ "${dir}/Sergent/Pyle.dat", { name => 'Pyle', rank => 'Sergent' } ],
          ],
          'Path resolution data is correct');


# This path spec has a hardcoded glob in it already
$bx = $bx = URT::Thing->define_boolexpr(name => 'Pyle');
ok($bx, 'Create boolexpr with just name');
@data = UR::DataSource::Filesystem->_replace_vars_with_values_in_pathname(
               $bx,
               ${tmpdir}.'/*/$rank/${name}.dat'
            );
is(scalar(@data), 1, 'property replacement for spec including a glob yielded one pathname');
#print Data::Dumper::Dumper(\@data);
is_deeply(\@data,
           [ [ "$tmpdir/*/*/Pyle.dat", { name => 'Pyle', '.__glob_positions__' => [ [$tmpdir_strlen+3, 'rank' ] ] }
             ]
           ],
           'Path resolution data is correct');

@data = UR::DataSource::Filesystem->_replace_glob_with_values_in_pathname(@{$data[0]});
is(scalar(@data), 3, 'Glob replacement yielded three possible pathnames');
@data = sort { $a->[0] cmp $b->[0] } @data;
is_deeply(\@data,
          [
              [ "${dir}/General/Pyle.dat", { name => 'Pyle', rank => 'General' } ],
              [ "${dir}/Private/Pyle.dat", { name => 'Pyle', rank => 'Private' } ],
              [ "${dir}/Sergent/Pyle.dat", { name => 'Pyle', rank => 'Sergent' } ],
          ],
          'Path resolution data is correct');



# Make a bx with no filters and two properties in the path spec
$bx = $bx = URT::Thing->define_boolexpr();
ok($bx, 'Create boolexpr with no filters');
@data = UR::DataSource::Filesystem->_replace_vars_with_values_in_pathname(
               $bx,
               ${tmpdir}.'/*/$rank/${name}.dat'
            );
is(scalar(@data), 1, 'property replacement for spec including a glob yielded one pathname');
#print Data::Dumper::Dumper(\@data);
is_deeply(\@data,
           [ [ "$tmpdir/*/*/*.dat", { '.__glob_positions__' => [ [$tmpdir_strlen+3, 'rank' ],[$tmpdir_strlen+5,'name' ] ] }
             ]
           ],
           'Path resolution data is correct');

@data = UR::DataSource::Filesystem->_replace_glob_with_values_in_pathname(@{$data[0]});
is(scalar(@data), 5, 'Glob replacement yielded one possible pathname');
@data = sort { $a->[0] cmp $b->[0] } @data;
is_deeply(\@data,
          [
              [ "${dir}/General/Halftrack.dat", { name => 'Halftrack', rank => 'General' } ],
              [ "${dir}/Private/Bailey.dat", { name => 'Bailey', rank => 'Private' } ],
              [ "${dir}/Private/Pyle.dat", { name => 'Pyle', rank => 'Private' } ],
              [ "${dir}/Sergent/Carter.dat", { name => 'Carter', rank => 'Sergent' } ],
              [ "${dir}/Sergent/Snorkel.dat", { name => 'Snorkel', rank => 'Sergent' } ],
          ],
          'Path resolution data is correct');



# a bx with no filters and three properties in the path spec
$bx = $bx = URT::Thing->define_boolexpr();
ok($bx, 'Create boolexpr with no filters');
@data = UR::DataSource::Filesystem->_replace_vars_with_values_in_pathname(
               $bx,
               ${tmpdir}.'/$other/$rank/${name}.dat'
        );
is(scalar(@data), 1, 'property replacement for spec including a glob yielded one pathname');
#print Data::Dumper::Dumper(\@data);
is_deeply(\@data,
           [ [ "$tmpdir/*/*/*.dat", { '.__glob_positions__' => [
                                                                 [$tmpdir_strlen+1, 'other' ],
                                                                 [$tmpdir_strlen+3,'rank'],
                                                                 [$tmpdir_strlen+5,'name' ],
                                                               ] }
             ]
           ],
           'Path resolution data is correct');

@data = UR::DataSource::Filesystem->_replace_glob_with_values_in_pathname(@{$data[0]});
is(scalar(@data), 5, 'Glob replacement yielded one possible pathname');
@data = sort { $a->[0] cmp $b->[0] } @data;
is_deeply(\@data,
          [
              [ "${dir}/General/Halftrack.dat", { other => 'extra_dir', name => 'Halftrack', rank => 'General' } ],
              [ "${dir}/Private/Bailey.dat",    { other => 'extra_dir', name => 'Bailey',    rank => 'Private' } ],
              [ "${dir}/Private/Pyle.dat",      { other => 'extra_dir', name => 'Pyle',      rank => 'Private' } ],
              [ "${dir}/Sergent/Carter.dat",    { other => 'extra_dir', name => 'Carter',    rank => 'Sergent' } ],
              [ "${dir}/Sergent/Snorkel.dat",   { other => 'extra_dir', name => 'Snorkel',   rank => 'Sergent' } ],
          ],
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
