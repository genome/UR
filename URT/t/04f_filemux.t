#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 16;

use IO::File;

use URT; # dummy namespace
use URT::DataSource::SomeFileMux;

&setup_files_and_classes();

my $obj = URT::Thing->get(thing_id => 1, thing_type => 'person');
ok($obj, 'Got a person thing with id 1');
is($obj->thing_name, 'Joel', 'Name is correct');
is($obj->thing_color, 'grey', 'Color is correct');
is($obj->thing_type, 'person', 'type is correct');

$obj = URT::Thing->get(thing_id => 6, thing_type => 'robot');
ok($obj, 'Got a robot thing with id 5');
is($obj->thing_name, 'Tom', 'Name is correct');
is($obj->thing_color, 'red', 'Color is correct');

$obj = URT::Thing->get(thing_id => 5, thing_type => 'person');
ok(!$obj, 'Correctly found no person thing with id 5');


my @objs = URT::Thing->get(thing_type => ['person','robot'], thing_id => 7);
is(scalar(@objs),1, 'retrieved a thing with id 7 that is either a person or robot');
is($objs[0]->thing_id, 7, 'The retrieved thing has the right id');
is($objs[0]->thing_type, 'robot', 'The retrieved thing is a robot');
is($objs[0]->thing_name, 'Gypsy', 'Name is correct');
is($objs[0]->thing_color, 'purple', 'Color is correct');



my $error_message;
UR::Context->message_callback('error', sub { $DB::single=1; $error_message = $_[0]->text });
$obj = eval { URT::Thing->get(thing_id => 2) };
ok(!$obj, "Correctly couldn't retrieve a Thing without a thing_type");
like($error_message, qr(Recursive entry.*URT::Thing), 'Error message did mention recursive call trapped');


sub setup_files_and_classes {
    my $dir = $URT::DataSource::SomeFileMux::BASE_PATH;
    my $delimiter = URT::DataSource::SomeFileMux->delimiter;

    my $file = "$dir/person";
    my $f = IO::File->new(">$file") || die "Can't open $file for writing: $!";
    $f->print(join($delimiter, qw(1 Joel grey)),"\n");
    $f->print(join($delimiter, qw(2 Mike blue)),"\n");
    $f->print(join($delimiter, qw(3 Frank black)),"\n");
    $f->print(join($delimiter, qw(4 Clayton green)),"\n");

    $f->close();

    $file = "$dir/robot";
    $f = IO::File->new(">$file") || die "Can't open $file for writing: $!";
    $f->print(join($delimiter, qw(5 Crow gold)),"\n");
    $f->print(join($delimiter, qw(6 Tom red)),"\n");
    $f->print(join($delimiter, qw(7 Gypsy purple)),"\n");
    $f->close();

    my $c = UR::Object::Type->define(
        class_name => 'URT::Thing',
        id_by => [
            thing_id => { is => 'Integer' },
        ],
        has => [
            thing_name => { is => 'String' },
            thing_color => { is => 'String' },
            thing_type => { is => 'String' },
        ],
        table_name => 'wefwef',
        data_source => 'URT::DataSource::SomeFileMux',
    );

    ok($c, 'Created class');
}


