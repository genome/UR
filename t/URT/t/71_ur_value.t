use warnings;
use strict;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use UR;
use Test::More tests => 16;

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

my $z = Test::Value->get('xyz');
ok($z,"get('xyz') returned on first call");

my $y = Test::Value->get('xyz');
ok($y,"get('xyz') returned on second call");

my $x = Test::Value->get(string => 'abc');
ok($x,"get(string => 'abc') returned on first call");

my $w = Test::Value->get(string => 'abc');
ok($w,"get(string => 'abc') returned on second call");

 
