#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use above "UR";

# Test PerlReference UR::Value Views
test_SCALAR_view();
test_ARRAY_view();
test_HASH_view();

done_testing();

sub test_SCALAR_view {
    my $view = UR::Value::View::Default::Xml->create();
    isa_ok($view, 'UR::Object::View', 'view');

    my $string = 'abc';
    my $scalar = \$string;
    my $scalar_object = UR::Value::SCALAR->get($scalar);
    isa_ok($scalar_object, 'UR::Value', 'scalar_object');

    $view->subject($scalar_object);
    my $xml = $view->content;
    $xml =~ tr/\n//d; # remove newlines
    $xml =~ s/>\s+</></g; # remove extra whitespace
    $xml =~ s/0x[a-f0-9]{7}//g; # remove memory addresses

    my $expected_xml = join('',
        '<?xml version="1.0"?>',
        '<object type="UR::Value::SCALAR" id="SCALAR()">',
            '<display_name>SCALAR()</display_name>',
            '<label_name>SCALA R</label_name>',
            '<types>',
                '<isa type="UR::Value::SCALAR"/>',
                '<isa type="UR::Value::PerlReference"/>',
                '<isa type="UR::Value"/>',
                '<isa type="UR::Object"/>',
            '</types>',
            '<perldata>',
                '<scalarref memory_address="">abc</scalarref>',
            '</perldata>',
        '</object>',
    );
    is($xml, $expected_xml, 'SCALAR xml matches expected output');
}

sub test_ARRAY_view {
    my $view = UR::Value::View::Default::Xml->create();
    isa_ok($view, 'UR::Object::View', 'view');

    my $array = [ 1, 2, 4 ];
    my $array_object = UR::Value::ARRAY->get($array);
    isa_ok($array_object, 'UR::Value', 'array_object');

    $view->subject($array_object);
    my $xml = $view->content;
    $xml =~ tr/\n//d; # remove newlines
    $xml =~ s/>\s+</></g; # remove extra whitespace
    $xml =~ s/0x[a-f0-9]{7}//g; # remove memory addresses

    my $expected_xml = join('',
        '<?xml version="1.0"?>',
        '<object type="UR::Value::ARRAY" id="ARRAY()">',
            '<display_name>ARRAY()</display_name>',
            '<label_name>ARRA Y</label_name>',
            '<types>',
                '<isa type="UR::Value::ARRAY"/>',
                '<isa type="UR::Value::PerlReference"/>',
                '<isa type="UR::Value"/>',
                '<isa type="UR::Object"/>',
            '</types>',
            '<perldata>',
                '<arrayref memory_address="">',
                    '<item key="0">1</item>',
                    '<item key="1">2</item>',
                    '<item key="2">4</item>',
                '</arrayref>',
            '</perldata>',
        '</object>',
    );
    is($xml, $expected_xml, 'ARRAY xml matches expected output');
}

sub test_HASH_view {
    my $view = UR::Value::View::Default::Xml->create();
    isa_ok($view, 'UR::Object::View', 'view');

    my $hash = { a => 1, b => 2, c => 4 };
    my $hash_object = UR::Value::HASH->get($hash);
    isa_ok($hash_object, 'UR::Value', 'hash_object');

    $view->subject($hash_object);
    my $xml = $view->content;
    $xml =~ tr/\n//d; # remove newlines
    $xml =~ s/>\s+</></g; # remove extra whitespace
    $xml =~ s/0x[a-f0-9]{7}//g; # remove memory addresses

    my $expected_xml = join('',
        '<?xml version="1.0"?>',
        '<object type="UR::Value::HASH" id="HASH()">',
            '<display_name>HASH()</display_name>',
            '<label_name>HAS H</label_name>',
            '<types>',
                '<isa type="UR::Value::HASH"/>',
                '<isa type="UR::Value::PerlReference"/>',
                '<isa type="UR::Value"/>',
                '<isa type="UR::Object"/>',
            '</types>',
            '<perldata>',
                '<hashref memory_address="">',
                    '<item key="a">1</item>',
                    '<item key="b">2</item>',
                    '<item key="c">4</item>',
                '</hashref>',
            '</perldata>',
        '</object>',
    );
    is($xml, $expected_xml, 'HASH xml matches expected output');
}
