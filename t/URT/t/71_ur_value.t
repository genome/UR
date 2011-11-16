use warnings;
use strict;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use UR;
use Test::More tests => 25;

my $s1 = UR::Value::Text->get('hi there');
ok($s1, 'Got an object for string "hi there"');
is($s1->id, 'hi there', 'It has the right id');

my $s2 = UR::Value::Text->get('hi there');
ok($s2, 'Got another object for the same string');
is($s1,$s2, 'They are the same object');

my $s3 = UR::Value::Text->get('something else');
ok($s3, 'Got an object for a different string');
isnt($s1,$s3, 'They are different objects');

my $s1ref = "$s1";
ok($s1->unload(), 'Unload the original string object');

isa_ok($s1, 'UR::DeletedRef');
isa_ok($s2, 'UR::DeletedRef');

$s1 = UR::Value::Text->get('hi there');
ok($s1, 're-get the original string object');
is($s1->id, 'hi there', 'It has the right id');
isnt($s1, $s1ref, 'It is not the original object reference');

UR::Object::Type->define(
    class_name => 'Test::Value',
    is => 'UR::Value',
    id_by => [
        string => { is => 'Text' }
    ]
);

my $x1 = Test::Value->get('xyz');
ok($x1,"get('xyz') returned on first call");

my $x2 = Test::Value->get('xyz');
ok($x2,"get('xyz') returned on second call");
is($x1, $x2, 'They were the same object');

my $a1 = Test::Value->get(string => 'abc');
ok($a1,"get(string => 'abc') returned on first call");

my $a2 = Test::Value->get(string => 'abc');
ok($a2,"get(string => 'abc') returned on second call");
is($a1, $a2, 'They were the same object');

my $n1 = Test::Value->get('123');
ok($n1, "get('123') returned on first call");
my $n2 = Test::Value->get(string => '123');
ok($n2,"get(string => '123') returned on second call");
is($n1, $n2, 'They were the same object');


my @o = Test::Value->get(['xyz','abc','123','456']);
is(scalar(@o), 4, 'Got 4 Test::Values in a single get()');
my %o = map { $_->id => $_ } @o;

is($o{'123'}, $n1, "Object with id '123' is the same as the one from earlier");
is($o{'abc'}, $a1, "Object with id 'abc' is the same as the one from earlier");
is($o{'xyz'}, $x1, "Object with id 'xyz' is the same as the one from earlier");

 
