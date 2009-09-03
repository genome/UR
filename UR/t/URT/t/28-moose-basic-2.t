
BEGIN {
    use Test::More;
    if ($ENV{UR_MOOSE}) { 
        plan tests => 36;
    }
    else {
        plan skip_all => ": only used when UR_MOOSE is set";
    }
}

{
    package Foo;
    use UR::Moose;
    has 'foo' => ( is => 'ro' );
    no Moose;
}

{
    package Bar;
    use UR::Moose;
    extends 'Foo';
    no Moose;
}

package main;

use strict;
use warnings FATAL => 'all';

for my $c (qw(Foo Bar)) {
    can_ok( $c, 'meta' );
    my $m = $c->meta;
    isa_ok( $m, 'UR::Meta::Class' );
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


    # make an object the "normal" way
    my $f = $c->new;
    isa_ok( $f, $c );
    isa_ok( $f, 'UR::Object' );
    can_ok( $f, 'foo' );
    is( $f->foo, undef );
    $f = $c->new( foo => 5 );
    isa_ok( $f, $c );
    can_ok( $f, 'foo' );
    is( $f->foo, 5 );

    # make an object the "meta" way
    $f = $m->new_object( foo => 7 );
    isa_ok( $f, $c );
    can_ok( $f, 'foo' );
    is( $f->foo, 7 );
}

my $a = Foo->meta->get_attribute('foo');
isa_ok( $a, 'UR::Meta::Attribute' );
is( $a->name, 'foo', 'name of foo attribute is foo' );
