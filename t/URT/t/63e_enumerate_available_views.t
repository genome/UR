#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

eval "use XML::LibXML";
if ($INC{"XML/LibXML.pm"}) {
    plan tests => 4;
}
else {
    plan skip_all => 'works only with systems which have XML::LibXML';
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
