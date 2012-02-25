use warnings;
use strict;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use UR;
use Test::More tests => 39;

my $s1 = UR::Value::Text->get('hi there');
ok($s1, 'Got an object for string "hi there"');
is($s1->id, 'hi there', 'It has the right id');

my $s2 = UR::Value::Text->get('hi there');
ok($s2, 'Got another object for the same string');
is($s1,$s2, 'They are the same object');

my $s3 = UR::Value::Text->get('something else');
ok($s3, 'Got an object for a different string');
isnt($s1,$s3, 'They are different objects');

my $s1_refaddr = Scalar::Util::refaddr($s1);
ok($s1->unload(), 'Unload the original string object');

isa_ok($s1, 'UR::DeletedRef');
isa_ok($s2, 'UR::DeletedRef');

$s1 = UR::Value::Text->get('hi there');
ok($s1, 're-get the original string object');
is($s1->id, 'hi there', 'It has the right id');
isnt(Scalar::Util::refaddr($s1), $s1_refaddr, 'It is not the original object reference');

UR::Object::Type->define(
    class_name => 'Test::Value',
    is => 'UR::Value',
    id_by => [
        string => { is => 'Text' }
    ]
);

eval { Test::Value->get() };
like($@, qr/Can't load an infinite set of Test::Value/,
     'Getting infinite set of Test::Values threw an exception');

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
is($o{'456'}->string, '456', 'The 4th value in the last get() constructed the correct object');

 

UR::Object::Type->define(
    class_name => 'Test::Value2',
    is => 'UR::Value',
    id_by => [
        string1 => { is => 'Text' },
        string2 => { is => 'Text' },
    ],
    has => [
        other_prop => { is => 'Text' },
    ],
);

eval { Test::Value2->get(string1 => 'abc') };
like($@, qr/Can't load an infinite set of Test::Value2/, 
     'Getting infinite set of Test::Value2s threw an exception');

$a1 = Test::Value2->get(string1 => 'qwe', string2 => undef);
ok($a1, "get(string1 => 'qwe', string2 => undef) worked");
$a2 = Test::Value2->get(id => 'qwe');
ok($a2, "get(id => 'qwe') worked");
is($a1, $a2, 'They were the same object');

$a1 = Test::Value2->get(string1 => 'abc', string2 => 'def');
ok($a1, 'get() with both ID properties worked');

my $sep = Test::Value2->__meta__->_resolve_composite_id_separator;
$a2 = Test::Value2->get('abc' . $sep . 'def');
ok($a2, 'get() with the composite ID property worked');
is($a1, $a2, 'They are the same object');
is($a1->other_prop, undef, 'The non-id property is undefined');

$x1 = Test::Value2->get(string1 => 'xyz', string2 => 'xyz', other_prop => 'hi there');
ok($x1, 'get() including a non-id property worked');
is($x1->other_prop, 'hi there', 'The non-id property has the right value');

TODO: {
    local $TODO = "Can't normalize a composite id in-clause rule";

    # This isn't working properly because of a shortcoming in BoolExpr normalization.  It ends up making
    # a rule like id => [abc,xyz], when we really want something like
    # ( string1 => 'abc' and string2 => 'abc) or ( string1 => 'xyz' and string2 => 'xyz')

    local $SIG{'__WARN__'} = sub {};   # Suppress warnings about is_unique during boolexpr construction
    @o = Test::Value2->get(['xyz'.$sep.'xyz', 'abc'.$sep.'abc']);
    is(scalar(@o), 2, 'get() with 2 composite IDs worked');
}


{ 
    local $SIG{'__WARN__'} = sub {};   # Suppress warnings about is_unique during boolexpr construction
    eval { Test::Value2->get(id => ['xyz'.$sep.'xyz', 'abc'.$sep.'abc'], other_prop => 'somethign else') };
    like($@, qr/Cannot load class Test::Value2 via UR::DataSource::Default when 'id' is a listref and non-id properties appear in the rule/,
     'Getting with multiple IDs and including non-id properites threw an exception');
}

