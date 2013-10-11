#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;
use Test::More;

my $test_obj = UR::Value->create('test value');

my $return_val_with_format_string = $test_obj->status_message('Hello, I like %s.', 'turkey sandwiches');
is($return_val_with_format_string, 'Hello, I like turkey sandwiches.',
    'When given multiple arguments, it treates it like a format string');

my $val_with_invalid_format_string = 'Hello, this is not a valid format string %J';
my $return_val_without_format_string = $test_obj->status_message($val_with_invalid_format_string);
is($val_with_invalid_format_string, $return_val_without_format_string,
    'When given a single argument, it does not run it through sprintf');

done_testing();
