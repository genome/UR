
use strict;
use warnings FATAL => 'all';

BEGIN {
    use Test::More;
    if ($ENV{UR_MOOSE}) { 
        plan tests => 14;
    }
    else {
        plan skip_all => ": only used when UR_MOOSE is set";
    }
};

sub class_isa_ok {
    ok($_[0]->isa($_[1]), "$_[0] isa $_[1]");
}

use UR;

use_ok('UR::Meta::Class');
isa_ok( UR::Meta::Class->meta, 'UR::Meta::Class' );
isa_ok( UR::Meta::Class->meta, 'Moose::Meta::Class' );
ok( UR::Object->isa('Moose::Object'), 'ur object isa moose object' );
ok( UR::Meta::Class->isa('UR::Object'),    'class isa object' );
ok( UR::Meta::Class->isa('Moose::Object'), 'class isa object' );
isa_ok( UR::Object->meta, 'UR::Meta::Class' );
isa_ok( UR::Object->meta, 'Moose::Meta::Class' );
is( UR::Object->meta->attribute_metaclass,
    'UR::Meta::Attribute', 'attribute metaclass is UR::Meta::Attribute' );

class_isa_ok( 'UR::Object', 'Moose::Object');
class_isa_ok( 'UR::Meta::Class', 'Moose::Meta::Class');
class_isa_ok( 'UR::Meta::Instance', 'Moose::Meta::Instance');
class_isa_ok( 'UR::Meta::Method', 'Moose::Meta::Method');
class_isa_ok( 'UR::Meta::Attribute', 'Moose::Meta::Attribute');


