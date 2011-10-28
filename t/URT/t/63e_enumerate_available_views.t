#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

BEGIN {
    eval "use XML::LibXSLT";
    if ($@ =~ qr(Can't locate XML/LibXSLT.pm in \@INC)) {
        plan skip_all => 'XML::LibXSLT does not exist on the system';
    } else {
        plan tests => 5;
        use_ok('UR::Object::View::Default::Xsl',  qw/url_to_type type_to_url/);
    }
}

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

use URT;

my $type = URT::Thingy->__meta__;
ok($type, 'got meta-object for URT::Thingy class');

my $view = $type->create_view(perspective => 'available-views', toolkit => 'xml');
isa_ok($view, 'UR::Object::View', 'created view for available views');

my $content = $view->content;
ok($content, 'generated content');

my $err = $view->error_message; #errors if views do not have perspective and toolkit set appropriately
ok(!$err, 'no errors in view creation');
