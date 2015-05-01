package UR::Role::PrototypeWithParams;

use strict;
use warnings;

# A plain-perl class to represent a role prototype bound to a set of params.
# It exists ephemerally as a class is composing its roles when using this
# syntax:
#
# class The::Class {
#     roles => [ The::Role->create(param => 'value') ],
# };

sub create {
    my($class, %params) = @_;
    unless (exists($params{prototype}) and exists($params{role_params})) {
        Carp::croak('prototype and role_params are required args to create()');
    }
    my $self = {};
    @$self{'prototype', 'role_params'} = delete @params{'prototype','role_params'};
    if (%params) {
        Carp::croak('Unrecognized params to create(): ' . Data::Dumper::Dumper(\%params));
    }

    return bless $self, $class;
}

sub instantiate_role_instance {
    my($self, $class_name) = @_;
    my %create_args = ( role_name => $self->role_name, class_name => $class_name );
    $create_args{role_params} = $self->role_params if $self->role_params;
    return UR::Role::Instance->create(%create_args);
}


# direct accessors
foreach my $accessor_name ( qw( prototype role_params ) ) {
    my $sub = sub {
        $_[0]->{$accessor_name};
    };
    no strict 'refs';
    *$accessor_name = $sub;
}

# accessors that delegate to the role prototype
foreach my $accessor_name ( qw( role_name methods overloads has requires attributes_have excludes
                                property_names property_data method_names
                                meta_properties_to_compose_into_classes ),
                            UR::Role::Prototype::meta_properties_to_compose_into_classes()
) {
    my $sub = sub {
        shift->{prototype}->$accessor_name(@_);
    };
    no strict 'refs';
    *$accessor_name = $sub;
}

1;
