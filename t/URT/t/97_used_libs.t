use strict;
use warnings;

use Test::More tests => 5;
require UR::Util;

my @used_libs;


@INC = ('/bar');
$ENV{PERL5LIB} = '/bar';
@used_libs = UR::Util::used_libs();
ok(eq_array(\@used_libs, []), 'no used_libs');


@INC = ('/foo');
$ENV{PERL5LIB} = '';
@used_libs = UR::Util::used_libs();
ok(eq_array(\@used_libs, ['/foo']), 'empty PERL5LIB');


@INC = ('/foo', '/bar', '/baz');
$ENV{PERL5LIB} = '/bar:/baz';
@used_libs = UR::Util::used_libs();
ok(eq_array(\@used_libs, ['/foo']), 'multiple dirs in PERL5LIB');


@INC = ('/foo', '/bar');
$ENV{PERL5LIB} = '/bar';
@used_libs = UR::Util::used_libs();
ok(eq_array(\@used_libs, ['/foo']), 'only one item in PERL5LIB (no trailing colon)');


@INC = ('/foo', '/bar', '/baz');
$ENV{PERL5LIB} = '/bar/:/baz';
@used_libs = UR::Util::used_libs();
ok(eq_array(\@used_libs, ['/foo']), 'first dir in PERL5LIB ends with slash (@INC may not have slash)');
