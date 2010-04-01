#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 3;

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
        cats    => { is => 'Cat', is_many => 1 },
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


my $pv = $p->create_view(
    toolkit => 'xml',
    aspects => [
        'name',
        'age',
        {
            name => 'cats',
            perspective => 'default',
            toolkit => 'xml',
            aspects => [
                'name',
                'age',
                'fluf',
                'owner'
            ],
        }
    ]
);
ok($pv, "got an XML viewer for the person");
print($pv->content);
print "After calling conetnt\n";
my $pv_expected_xml = '';
is($pv->content,$pv_expected_xml,"XML is as expected for the person view");

my $c1v = $c1->create_view(toolkit => 'text');
ok($c1v, 'Created text viewer for a cat');
print($c1v->content);
ok($c1v, "got a text viewer for one of the cats");
my $c1v_expected_xml = '';
is($c1v->content,$c1v_expected_xml,"text is as expected for the cat view");

