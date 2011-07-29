use Test::More;

use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;

plan tests => 5;

# First, make a couple of classes we can point to
my $c = UR::Object::Type->define(
    class_name => 'URT::Related',
    id_by => [
        related_id  => { is => 'String' },
        related_id2 => { is => 'String' },
    ],
    has => [
        related_value => { is => 'String'},
    ],
);

ok($c, 'Defined URT::Related class');

$c = UR::Object::Type->define(
    class_name => 'URT::Parent',
    id_by => [
        parent_id => { is => 'String' },
    ],
    has => [
        parent_value => { is => 'String' },
    ],
);
ok($c, 'Defined URT::Parent class');

$c = UR::Object::Type->define(
    class_name => 'URT::Remote',
    id_by => [
        remote_id => { is => 'Integer' },
    ],
    has => [
#        test_obj => { is => 'URT::TestClass', id_by => ['prop1','prop2','prop3'] },
        something => { is => 'String' },
    ],
);
ok($c, 'Defined URT::Remote class');

# Make up a class definition with all the different kinds of properties we can think of...
# FIXME - I'm not sure how the attributes_have and id_implied stuff is meant to work
my $test_class_definition =
    q(    is => [ 'URT::Parent' ],
    table_name => 'PARENT_TABLE',
    attributes_have => [
        meta_prop_a => { is => 'Boolean', is_optional => 1 },
        meta_prop_b => { is => 'String' },
    ],
    subclassify_by => 'my_subclass_name',
    id_by => [
        another_id => { is => 'String', 
            doc => 'blahblah' },
        related => { is => 'URT::Related', id_by => [ 'parent_id', 'related_id' ], 
                      doc => 'related' },
        foobaz => { is => 'Integer' },
    ],
    has => [
        property_a          => { is => 'String', meta_prop_a => 1 },
        property_b          => { is => 'Integer', is_abstract => 1, meta_prop_b => 'metafoo', doc => 'property_b' },
        calc_sql            => { calculate_sql => q(to_upper(property_b)) },
        some_enum           => { is => 'Integer', column_name => 'SOME_ENUM', valid_values => [100,200,300] },
        another_enum        => { is => 'String', column_name => 'different_name', valid_values => ["one","two","three",3,"four"] },
        my_subclass_name    => { is => 'Text', calculate_from => [ 'property_a', 'property_b' ], calculate => q("URT::TestClass") },
        subclass_by_prop    => { is => 'String', implied_by => 'subclass_by_obj' },
        subclass_by_id      => { is => 'Integer', implied_by => 'subclass_by_obj' },
        subclass_by_obj     => { is => 'UR::Object', id_by => 'subclass_by_id', id_class_by => 'subclass_by_prop' },
    ],
    has_many => [
        property_cs => { is => 'String', is_optional => 1 },
        remotes => { is => 'URT::Remote', reverse_as => 'testobj', where => [ something => { operator => 'like', value => '%match%' } ] },
    ],
    has_optional => [
        property_d => { is => 'Number' },
        calc_perl  => { calculate_from => [ 'property_a', 'property_b' ],
                        calculate => q($property_a . $property_b) },
        another_related => { is => 'URT::Related', id_by => [ 'rel_id1', 'rel_id2' ], where => [ property_a => 'foo' ] },
        related_value => { is => 'StringSubclass', via => 'another_related' },
        related_value2 => { is => 'StringSubclass', via => 'another_related', to => 'related_value', is_mutable => 1 },
    ],
    schema_name => 'SomeFile',
    data_source => 'URT::DataSource::SomeFile',
    id_generator => 'the_sequence_seq',
    doc => 'Hi there',
);
my $orig_test_class = $test_class_definition;
my $test_class_meta = eval "UR::Object::Type->define(class_name => 'URT::TestClass', $test_class_definition);";
ok($test_class_meta, 'Defined URT::TestClass class');
if ($@) {
    diag("Errors from class definition:\n$@");
    exit(1);
}

my $string = $test_class_meta->resolve_class_description_perl();
my $orig_string = $string;

# Normalize them by removing newlines, and multiple spaces
$test_class_definition =~ s/\n//gm;
$test_class_definition =~ s/\s+/ /gm;
$string =~ s/\n//gm;
$string =~ s/\s+/ /gm;

my $diffcmd = 'sdiff -s ';

if ($string ne $test_class_definition) {
    ok(0, 'Rewritten class definition matches original');
    #is($string, $test_class_definition, 'Rewritten class definition matches original');
    diag("Original definition string:\n$orig_test_class\n");
    diag("Generated definition:\n$orig_string\n");
    IO::File->new('>/tmp/old')->print($orig_test_class);
    IO::File->new('>/tmp/new')->print($orig_string);
    system "$diffcmd/tmp/old /tmp/new";
} else {
    ok(1, 'Rewritten class definition matches original');
}

