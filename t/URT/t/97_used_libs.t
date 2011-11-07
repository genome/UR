use strict;
use warnings;

use Test::More;
require UR::Util;

{
    local @INC = ('/bar');
    local $ENV{PERL5LIB} = '/bar';
    my @used_libs = UR::Util::used_libs();
    ok(eq_array(\@used_libs, []), 'no used_libs');
}
{
    local @INC = ('/foo');
    local $ENV{PERL5LIB} = '';
    my @used_libs = UR::Util::used_libs();
    ok(eq_array(\@used_libs, ['/foo']), 'empty PERL5LIB');
}
{
    local @INC = ('/foo', '/bar', '/baz');
    local $ENV{PERL5LIB} = '/bar:/baz';
    my @used_libs = UR::Util::used_libs();
    ok(eq_array(\@used_libs, ['/foo']), 'multiple dirs in PERL5LIB');
}
{
    local @INC = ('/foo', '/bar');
    local $ENV{PERL5LIB} = '/bar';
    my @used_libs = UR::Util::used_libs();
    ok(eq_array(\@used_libs, ['/foo']), 'only one item in PERL5LIB (no trailing colon)');
}
{
    local @INC = ('/foo', '/bar', '/baz');
    local $ENV{PERL5LIB} = '/bar/:/baz';
    my @used_libs = UR::Util::used_libs();
    ok(eq_array(\@used_libs, ['/foo']), 'first dir in PERL5LIB ends with slash (@INC may not have slash)');
}
{
    local @INC = ('/foo', '/foo', '/bar');
    local $ENV{PERL5LIB} = '/bar';
    my @used_libs = UR::Util::used_libs();
    ok(eq_array(\@used_libs, ['/foo']), 'remove duplicate elements from used_libs');
}
{
    local @INC = ('/foo');
    local $ENV{PERL5LIB} = '';
    local $ENV{PERL_USED_ABOVE} = '/foo/';
    my @used_libs = UR::Util::used_libs();
    ok(eq_array(\@used_libs, ['/foo']), 'remove trailing slash from used_libs');
}

done_testing();
