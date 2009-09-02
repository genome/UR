
package UR::Moose;

# Moosify UR Objects :)


moosify() if $ENV{UR_MOOSE};

use Carp ();

sub import {

    my ( $class, $arg ) = @_;
    my $caller = caller();

    strict->import;
    warnings->import;

    # we should never export to main
    return if $caller eq 'main';

    # deal with $arg
    if ( defined($arg) ) {
        if ( !ref($arg) || ref($arg) ne 'HASH' ) {
            Carp::croak(q{argument to 'use UR' must be a hashref });
        }
    }
    else {
        $arg = {};
    }
    $arg->{init_meta} = [ 'UR::Object', 'UR::Meta::Class' ]
        if ( !$arg->{init_meta} );
    
    Moose::init_meta( $caller, @{ $arg->{init_meta} } );
    Moose->import( { into => $caller } );

    return 1;
}

our $moosified = 0;

sub moosify {
    return if $moosified;
    $moosified = 1;

    require Moose;
    
#    @UR::Object::ISA          = ('Moose::Object');
    @UR::Object::ISA          = ( 'Moose::Object', 'UR::ModuleBase' );
    @UR::Meta::Class::ISA     = ('Moose::Meta::Class');
    @UR::Meta::Instance::ISA  = ('Moose::Meta::Instance');
    @UR::Meta::Method::ISA    = ('Moose::Meta::Method');
    @UR::Meta::Attribute::ISA = ('Moose::Meta::Attribute');
    
    my @metaclasses = (
        'attribute_metaclass' => 'UR::Meta::Attribute',
        'method_metaclass'    => 'UR::Meta::Method',
        'instance_metaclass'  => 'UR::Meta::Instance',
    );
    
    UR::Meta::Class->reinitialize( 'UR::Meta::Instance'  => @metaclasses );
    UR::Meta::Class->reinitialize( 'UR::Object'          => @metaclasses );
    UR::Meta::Class->reinitialize( 'UR::Meta::Method'    => @metaclasses );
    UR::Meta::Class->reinitialize( 'UR::Meta::Attribute' => @metaclasses );
    UR::Meta::Class->reinitialize( 'UR::Meta::Class'     => @metaclasses );

    
    require UR::Object;
    require UR::Meta::Attribute;
    require UR::Meta::Method;
    require UR::Meta::Instance;
    require UR::Meta::Class;

#    Moose::init_meta( 'UR::Object', 'Moose::Object', 'UR::Meta::Class' );
#    Moose->import( { into => 'UR::Object' } );

#    package UR::ModuleBase;
#    use Moose::Role;
#    Moose::Role->import;

#    package UR::Object;
#    with 'UR::ModuleBase';
#    UR::ModuleBase->meta->apply(UR::Object->meta);
#                    $roles[0]->meta->apply($meta);
    
#    UR::Object->meta->superclasses(['Moose::Object', 'UR::ModuleBase']);
#    UR::Object->meta->superclasses('Moose::Object', 'UR::ModuleBase');

#    print "@UR::Object::ISA\n";
#    my @isa = UR::Object->meta->superclasses;
#    print "superclasses: @isa\n";

#    print "MOOSIFY!\n";

    return 1;
}


1;

