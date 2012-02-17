#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../../lib";
use lib File::Basename::dirname(__FILE__)."/../../..";
use URT;
use Test::More tests => 8;

use IO::File;
use File::Temp;
use Sub::Install;

# map people to their rank and serial nubmer
my %people = ( Pyle => { rank => 'Private', serial => 123 },
               Bailey => { rank => 'Private', serial => 234 },
               Snorkel => { rank => 'Sergent', serial => 345 },
               Carter => { rank => 'Sergent', serial => 456 },
               Halftrack => { rank => 'General', serial => 567 },
               Bob => { rank => 'General', serial => 678 },
             );

my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
ok($tmpdir, "Created temp dir $tmpdir");
while (my($name,$data) = each %people) {
    ok(_create_data_file($tmpdir,$data->{'rank'},$name,$data->{'serial'}), "Create file for $name");
}


ok(UR::Object::Type->define(
    class_name => 'URT::Soldier',
    id_by => [
        serial => { is => 'Number' }
    ],
    has => [
        name => { is => 'String' },
        rank => { is => 'String' },
    ],
    #data_source => { uri => "file:$tmpdir/\$rank.dat" }
    data_source => { is => 'UR::DataSource::Filesystem',
                     path  => $tmpdir.'/$rank.dat',
                     columns => ['name','serial'],
                     delimiter => "\t",
                   },
    ),
    'Defined class for soldiers');


my @objs = URT::Soldier->get(name => 'Pyle', rank => 'Private');
is(scalar(@objs), 1, 'Got one Private named Pyle');
ok(_compare_to_expected($objs[0], 'Pyle'), 'Object has the correct data');

@objs = URT::Soldier->get(rank => 'General');
is(scalar(@objs), 2, 'Got two soldiers with rank General');
ok(_compare_to_expected($objs[0], 'Halftrack'), 'First object has correct data');
ok(_compare_to_expected($objs[1], 'Bob'), 'Second object has correct data');








sub _compare_to_expected {
    my($obj,$name) = @_;

    return unless $obj->name eq $name;

    my $expected = $people{$name};
    return unless $expected;
    return unless $obj->id eq $expected->{'serial'};
    return unless $obj->serial eq $expected->{'serial'};
    return unless $obj->rank eq $expected->{'rank'};
    return 1;
}

sub _create_data_file {
    my($dir,$rank,$name,$serial) = @_;

    my $pathname = $dir . '/' . $rank . '.dat';
    my $f = IO::File->new($pathname, '>>');
    die "Can't create file $pathname: $!" unless $f;

    $f->print("$name\t$serial\n");
    $f->close;
    1;
}
