
use strict;
use warnings FATAL => 'all';

use Test::More;
if ($ENV{UR_MOOSE}) { 
    plan tests => 26;
}
else {
    plan skip_all => ": only used when UR_MOOSE is set";
}


use_ok('UR');

my @class = (
    'UR::Meta::Attribute',
    'UR::Meta::Class',
    'UR::Object',
    'UR::Meta::Instance',
    'UR::Meta::Method',
);

for my $c (@class) {
    ok( $c->isa('UR::Object'), "$c isa UR::Object" );
    is( ref( $c->meta ),
        'UR::Meta::Class', "$c metaclass is UR::Meta::Class" );
    is( $c->meta->attribute_metaclass,
        'UR::Meta::Attribute',
        "$c attribute metaclass is UR::Meta::Attribute" );
    is( $c->meta->instance_metaclass,
        'UR::Meta::Instance',
        "$c instance metaclass is UR::Meta::Instance" );
    is( $c->meta->method_metaclass,
        'UR::Meta::Method', "$c method metaclass is UR::Meta::Method" );
}

