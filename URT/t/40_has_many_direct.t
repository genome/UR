
use strict;
use warnings;
use UR;
use Test::More tests => 15;

# make sure the INDIRECT stuff still works

class Order {
    has => [],
    has_many => [
        lines => { is => "Line" },
        line_numbers => { via => "lines", to => "line_num" },
    ]
};

class Line {
    id_by => [
        order => { is => "Order", id_by => "order_id" },
        line_num => { is => "Number" },
    ],
};

my $o = Order->create(
    lines => [ 1, 2, 17 ]
);

my @lines = $o->lines;
my @line_nums = sort $o->line_numbers();
is("@line_nums", "1 17 2", "has-many with INDIRECT relationships still works correctly, now trying the new stuff...");


class FileList {
    has => [
        files => { is => 'FileName', is_many => 1 }, 
    ]
};

#print Data::Dumper::Dumper(MyCommand->get_class_object);
#my $m = MyCommand->get_class_object->get_property_meta_by_name("files");
#print Data::Dumper::Dumper($m);

my $list1 = FileList->create(
    files => ['a','b','c']
);
ok($list1, "made new object");

my @f = $list1->files();
is(scalar(@f),3,"got back expected value count");
is("@f", "a b c", "got back expected values: @f");

my $new = $list1->add_file("d");
is($new,"d","added a new value");
@f = $list1->files();
is(scalar(@f),4,"got expected value count");
is("@f","a b c d", "got expected values: '@f'");

my $list2 = FileList->create();
my $fx = $list2->file("xxx");
is($fx,undef,"correctly failed to find a made-up value");
my $f1 = $list2->add_file("aaa");
is($f1,"aaa","added a new value, retval is correct");
my $f1r = $list2->file("aaa");
is($f1r,$f1,"got it back through single accessor");
@f = $list2->files;
is(scalar(@f),1,"list has expected count");
is($f[0],$f1,"items are correct");
my $f2 = $list2->add_file("bbb");
my $f2r = $list2->file("bbb");
is($f2,$f2r,"added another file and got it back correctly: $f2");
@f = $list2->files;
is(scalar(@f),2,"list has expected count");
is("@f","aaa bbb","items are correct");


