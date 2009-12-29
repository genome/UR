#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 10;

#use File::Basename;
#use lib File::Basename::dirname(__FILE__)."/../..";

use above 'UR';

class Animal {
    has => [
        name    => { is => 'Text' },
        age     => { is => 'Number' },
    ]
};

class Person {
    is => 'Animal',
    has => [
        cats    => { is => 'Cat', is_many => 1, reverse_as => 'owner' },
    ]
};

class Cat {
    is => 'Animal',
    has => [
        fluf    => { is => 'Number' },
        owner   => { is => 'Person', id_by => 'owner_id' },
    ]
};

my $p = Person->create(name => 'Fester', age => 99);
    ok($p, "made a test person object to have cats");

my $c1 = Cat->create(name => 'fluffy', age => 2, owner => $p, fluf => 11);
    ok($c1, "made a test cat 1");

my $c2 = Cat->create(name => 'nestor', age => 8, owner => $p, fluf => 22);
    ok($c2, "made a test cat 2");

my @c = $p->cats();
is("@c","$c1 $c2", "got expected cat list for the owner");

#########

note('view 1: no aspects');
my $pv1 = $p->create_view(
    toolkit => 'text',
    aspects => [ ]
);
ok($pv1, "got an XML viewer $pv1 for the object $p");

my @a = $pv1->aspects();
is(scalar(@a),0,"got expected aspect list @a")
    or diag(Data::Dumper::Dumper(@a));

my @an = $pv1->aspect_names();
is("@an","","got expected aspect list @an");


#########

note('view 2: simple aspects');
my $pv2 = $p->create_view(
    toolkit => 'text',
    aspects => [
        'name',
        'age',
        'cats',
    ]
);
ok($pv2, "got an XML viewer $pv2 for the object $p");

@a = $pv2->aspects();
is(scalar(@a),3,"got expected aspect list @a")
 or diag(Data::Dumper::Dumper(@a));

@an = $pv2->aspect_names();
is("@an","name age cats","got expected aspect list @an");

#########

note('view 3: aspects with properties');

my $pv3 = $p->create_view(
    toolkit => 'text',
    aspects => [
        { name => 'name', label => 'NAME' },
        'age',
        { 
            name => 'cats', 
            label => 'Kitties', 
        },
    ]
);
ok($pv3, "got an XML viewer $pv3 for the object $p");

@a = $pv3->aspects();
is(scalar(@a),3,"got expected aspect list @a");
diag(Data::Dumper::Dumper(@a));

@an = $pv3->aspect_names();
is("@an","name age cats","got expected aspect list @an");

my $s = $pv3->subject;
is($s, $p, "subject is the original model object");

my $w = $pv3->widget;
print $w->getlines,"\n";

#######



__END__
print($pv->widget);
my $pv_expected_xml = undef;
is($pv->widget,$pv_expected_xml,"XML is as expected for the person view");

my $c1v = $c1->create_viewer(toolkit => 'text');
print($c1v->buf);
ok($c1v, "got an XML viewer for one of the cats");
my $c1v_expected_xml = '';
is($c1v->buf,$c1v_expected_xml,"XML is as expected for the cat view");

