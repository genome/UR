package UR::Role;

use strict;
use warnings;

use UR;
use UR::Object::Type::InternalAPI;
use UR::Util;

UR::Object::Type->define(
    class_name => 'UR::Role',
    doc => 'Object representing a role',
    id_by => 'role_name',
    has => [
        role_name   => { is => 'Text', doc => 'Package name identifying the role' },
        methods     => { is => 'HASH', doc => 'Map of method names and coderefs' },
        has         => { is => 'ARRAY', doc => 'List of properties and their definitions' },
        roles       => { is => 'ARRAY', doc => 'List of other role names composed into this role' },
        requires    => { is => 'ARRAY', doc => 'List of properties required of consuming classes' },
        attributes_have => { is => 'HASH', doc => 'Meta-attributes for properites' },
        map { $_ => _get_property_desc_from_ur_object_type($_) }
                                meta_properties_to_compose_into_classes(),
    ],
    is_transactional => 0,
);

sub property_data {
    my($self, $property_name) = @_;
    return $self->has->{$property_name};
}

sub property_names {
    my $self = shift;
    return keys %{ $self->has };
}

sub method_names {
    my $self = shift;
    return keys %{ $self->methods };
}

sub meta_properties_to_compose_into_classes {
    return qw( is_abstract is_final is_singleton
               composite_id_separator id_generator valid_signals 
               subclassify_by subclass_description_preprocessor sub_classification_method_name
               sub_classification_meta_class_name
               schema_name data_source_id table_name select_hint join_hint );
}

sub define {
    my $class = shift;
    my $desc = $class->_normalize_role_description(@_);

    unless ($desc->{role_name}) {
        Carp::croak(q('role_name' is a required parameter for defining a role));
    }

    my $methods = _introspect_methods($desc->{role_name});
    my $role = UR::Role->__define__(%$desc, methods => $methods);
    return $role;
}

our @ROLE_DESCRIPTION_KEY_MAPPINGS = (
    @UR::Object::Type::CLASS_DESCRIPTION_KEY_MAPPINGS_COMMON_TO_CLASSES_AND_ROLES,
    [ role_name             => qw// ],
    [ methods               => qw// ],
    [ requires              => qw// ],
);

sub _normalize_role_description {
    my $class = shift;
    my $old_role = { @_ };

    my $role_name = delete $old_role->{role_name};

    my $new_role = {
        role_name => $role_name,
        has => {},
        attributes_have => {},
        UR::Object::Type::_canonicalize_class_params($old_role, \@ROLE_DESCRIPTION_KEY_MAPPINGS),
    };

    unless (UR::Util::ensure_arrayref($new_role, 'requires')) {
        Carp::croak("The 'requires' metadata for role $role_name must be an arrayref");
    }

    # UR::Object::Type::_normalize_class_description_impl() copies these over before
    # processing the properties.  We need to, too
    @$old_role{'has', 'attributes_have'} = @$new_role{'has','attributes_have'};
    @$new_role{'has','attributes_have'} = ( {}, {} );
    UR::Object::Type::_process_class_definition_property_keys($old_role, $new_role);
    _complete_property_descriptions($new_role);
    
    $new_role->{methods} = UR::Util::coderefs_for_package($role_name);
    return $new_role;
}

sub _complete_property_descriptions {
    my $role_desc = shift;

    # stole from UR::Object::Type::_normalize_class_description_impl()
    my $properties = $role_desc->{has};
    foreach my $property_name ( keys %$properties ) {
        my $old_property = $properties->{$property_name};
        my %new_property = UR::Object::Type->_normalize_property_description1($property_name, $old_property, $role_desc);
        delete $new_property{class_name};  # above normalizer fills this in as undef
        $properties->{$property_name} = \%new_property;
    }
}

my %property_definition_key_to_method_name = (
    is => 'data_type',
    len => 'data_length',
);

sub _get_property_desc_from_ur_object_type {
    my $property_name = shift;

    my $prop_meta = UR::Object::Property->get(class_name => 'UR::Object::Type', property_name => $property_name);
    Carp::croak("Couldn't get UR::Object::Type property meta for $property_name") unless $prop_meta;

    # These properties' definition key is the same as the method name
    my %definition = map { $_ => $prop_meta->$_ }
                     grep { defined $prop_meta->$_ }
                     qw( is_many is_optional is_transient is_mutable default_value doc );

    # These have a translation
    while(my($key, $method) = each(%property_definition_key_to_method_name)) {
        $definition{$key} = $prop_meta->$method;
    }

    # For any UR::Object::Type properties that are required or have a default value,
    # those don't apply to Roles
    $definition{is_optional} = 1;
    delete $definition{default_value};

    return \%definition;
}

sub _introspect_methods {
    my $role_name = shift;

    return UR::Util::coderefs_for_package($role_name);
}

sub _dynamically_load_role {
    my($class, $role_name) = @_;

    if (my $already_exists = $class->is_loaded($role_name)) {
        return $already_exists;
    }

    if (UR::Util::use_package_optimistically($role_name)) {
        if (my $role = $class->is_loaded($role_name)) {
            return $role;
        } else {
            die qq(Cannot dynamically load role '$role_name': The module loaded but did not define a role.\n);
        }
    } else {
        die qq(Cannot dynamically load role '$role_name': No module exists with that name.\n);
    }
}

1;

__END__

=pod

=head1 NAME

UR::Role - Roles in UR, an alternative to inheritance

=head1 SYNOPSIS

  package My::Role;
  role My::Role {
      has => [
          role_property => { is => 'String' },
          another_prop  => { is => 'Integer' },
      },
      requires => ['class_method'],
  };
  sub role_method { ... }


  package My::Class;
  class My::Class {
      has => [
          class_property => { is => 'Integer ' },
      ],
      roles => ['My::Role'],
  };
  sub class_method { ... }

  my $obj = My::Class->new();
  $obj->does('My::Role');  # true

=head1 DESCRIPTION

Roles are used to encapsulate a piece of behavior to be used in other classes.
They have properties and methods that get melded into any class that composes
them.  A Role can require any composing class to implement a list of methods.

=cut
