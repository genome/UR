package UR::Role;

use strict;
use warnings;

use UR;
use UR::Object::Type::InternalAPI;
use UR::Util;
use UR::AttributeHandlers;

use Scalar::Util qw(blessed);
use List::MoreUtils qw(any);
use Carp;
our @CARP_NOT = qw(UR::Object::Type);

use Exporter 'import';
our @EXPORT = qw(defer);

Class::Autouse->sugar(\&_define_role);

UR::Object::Type->define(
    class_name => 'UR::Role',
    doc => 'Object representing a role',
    id_by => 'role_name',
    has => [
        role_name   => { is => 'Text', doc => 'Package name identifying the role' },
        methods     => { is => 'HASH', doc => 'Map of method names and coderefs' },
        overloads   => { is => 'HASH', doc => 'Map of overload keys and coderefs' },
        has         => { is => 'ARRAY', doc => 'List of properties and their definitions' },
        roles       => { is => 'ARRAY', doc => 'List of other role names composed into this role' },
        requires    => { is => 'ARRAY', doc => 'List of properties required of consuming classes' },
        attributes_have => { is => 'HASH', doc => 'Meta-attributes for properites' },
        excludes    => { is => 'ARRAY', doc => 'List of Role names that cannot compose with this role' },
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
    return qw( is_abstract is_final is_singleton doc
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
    my $overloads = _introspect_overloads($desc->{role_name});

    my $extra = delete $desc->{extra};
    my $role = UR::Role->__define__(%$desc, methods => $methods, overloads => $overloads);

    if ($extra and %$extra) {
        $role->UR::Object::Type::_apply_extra_attrs_to_class_or_role($extra);
    }

    return $role;
}

our @ROLE_DESCRIPTION_KEY_MAPPINGS = (
    @UR::Object::Type::CLASS_DESCRIPTION_KEY_MAPPINGS_COMMON_TO_CLASSES_AND_ROLES,
    [ role_name             => qw// ],
    [ methods               => qw// ],
    [ requires              => qw// ],
    [ excludes              => qw// ],
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

    # The above call to _canonicalize_class_params removed recognized keys.  Anything
    # left over wasn't recognized
    $new_role->{extra} = $old_role;

    foreach my $key (qw( requires excludes ) ) {
        unless (UR::Util::ensure_arrayref($new_role, $key)) {
            Carp::croak("The '$key' metadata for role $role_name must be an arrayref");
        }
    }

    # UR::Object::Type::_normalize_class_description_impl() copies these over before
    # processing the properties.  We need to, too
    @$old_role{'has', 'attributes_have'} = @$new_role{'has','attributes_have'};
    @$new_role{'has','attributes_have'} = ( {}, {} );
    UR::Object::Type::_process_class_definition_property_keys($old_role, $new_role);
    _complete_property_descriptions($new_role);

    _add_deferred_values_to_required($new_role);
    
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

sub _add_deferred_values_to_required {
    my $role_desc = shift;

    my @deferred = grep { $_->id ne 'class' }
                    UR::Role::DeferredValue->search_for_deferred_values_in_struct($role_desc);
    if (@deferred) {
        $role_desc->{requires} ||= [];
        push @{$role_desc->{requires}}, map { $_->id } @deferred;
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

{
    my @overload_ops;
    sub _all_overload_ops {
        @overload_ops = map { split /\s+/ } values(%overload::ops) unless @overload_ops;
        @overload_ops;
    }
}

sub _introspect_methods {
    my $role_name = shift;

    my $subs = UR::Util::coderefs_for_package($role_name);
    delete $subs->{__import__};  # don't allow __import__ to be exported to a class's namespace
    delete @$subs{ map { "($_" } ( _all_overload_ops, ')', '(' ) };
    return $subs;
}

sub _introspect_overloads {
    my $role_name = shift;

    return {} unless overload::Overloaded($role_name);

    my %overloads;
    my $stash = do {
        no strict 'refs';
        \%{$role_name . '::'};
    };
    foreach my $op ( _all_overload_ops ) {
        my $op_key = $op eq 'fallback' ? ')' : $op;
        my $overloaded = $stash->{'(' . $op_key};

        if ($overloaded) {
            my $subref = *{$overloaded}{CODE};
            $overloads{$op} = $subref eq \&overload::nil
                                ? ${*{$overloaded}{SCALAR}} # overridden with string method name
                                : $subref; # overridden with a subref
        }
    }
    return \%overloads;
}

# Called by UR::Object::Type::Initializer::compose_roles to apply a role name
# to a partially constructed class description
sub _apply_roles_to_class_desc {
    my($class, $desc) = @_;
    if (ref($class) or ref($desc) ne 'HASH') {
        Carp::croak('_apply_roles_to_class_desc() must be called as a class method on a basic class description');
    }

    return unless ($desc->{roles} and @{ $desc->{roles} });
    my @role_objs = $class->_dynamically_load_roles_for_class_desc($desc);

    $class->_validate_role_exclusions($desc);
    $class->_validate_role_requirements($desc);

    my $properties_to_add = _collect_properties_from_roles($desc, @role_objs);
    my $meta_properties_to_add = _collect_meta_properties_from_roles($desc, @role_objs);
    my $overloads_to_add = _collect_overloads_from_roles($desc, @role_objs);

    UR::Role::DeferredValue->apply_deferred_values_in_struct($desc->{class_name}, [ $properties_to_add, $meta_properties_to_add, $overloads_to_add ]);

    _import_methods_from_roles_into_namespace($desc->{class_name}, \@role_objs);
    _apply_overloads_to_namespace($desc->{class_name}, $overloads_to_add);

    my $valid_signals = delete $meta_properties_to_add->{valid_signals};
    my @meta_prop_names = keys %$meta_properties_to_add;
    @$desc{@meta_prop_names} = @$meta_properties_to_add{@meta_prop_names};
    if ($valid_signals) {
        push @{$desc->{valid_signals}}, @$valid_signals;
    };

    my @property_names = keys %$properties_to_add;
     @{$desc->{has}}{@property_names} = @$properties_to_add{@property_names};
}

sub _dynamically_load_roles_for_class_desc {
    my($class, $desc) = @_;

    my(@role_objs, $last_role, $exception);
    do {
        local $@;
        eval {
            @role_objs = map
                            { $last_role = $_ and $class->_dynamically_load_role($_) }
                            @{ $desc->{roles} };
        };
        $exception = $@;
    };
    if ($exception) {
        my $class_name = $desc->{class_name};
        Carp::croak("Cannot apply role $last_role to class $class_name: $exception");
    }
    return @role_objs;
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

sub _collect_properties_from_roles {
    my($desc, @role_objs) = @_;

    my $properties_from_class = $desc->{has};

    my(%properties_to_add, %source_for_properties_to_add);
    foreach my $role ( @role_objs ) {
        my @role_property_names = $role->property_names;
        foreach my $property_name ( @role_property_names ) {
            my $prop_definition = $role->property_data($property_name);
            if (my $conflict = $source_for_properties_to_add{$property_name}) {
                Carp::croak(sprintf(q(Cannot compose role %s: Property '%s' conflicts with property in role %s),
                                    $role->role_name, $property_name, $conflict));
            }

            $source_for_properties_to_add{$property_name} = $role->role_name;

            next if exists $properties_from_class->{$property_name};

            $properties_to_add{$property_name} = $prop_definition;
        }
    }
    return \%properties_to_add;
}

sub _collect_overloads_from_roles {
    my($desc, @role_objs) = @_;

    my $overloads_from_class = _introspect_overloads($desc->{class_name});

    my(%overloads_to_add, %source_for_overloads_to_add);
    my $fallback_validator = _create_fallback_validator();

    foreach my $role ( @role_objs ) {
        my $role_name = $role->role_name;
        my $overloads_this_role = $role->overloads;

        $fallback_validator->($role_name, $overloads_this_role->{fallback});
        while( my($op, $impl) = each(%$overloads_this_role)) {
            next if ($op eq 'fallback');
            if (my $conflict = $source_for_overloads_to_add{$op}) {
                Carp::croak("Cannot compose role $role_name: Overload '$op' conflicts with overload in role $conflict");
            }
            $source_for_overloads_to_add{$op} = $role_name;

            next if exists $overloads_from_class->{$op};

            $overloads_to_add{$op} = $impl;
        }
    }

    my $fallback = $fallback_validator->();
    $overloads_to_add{fallback} = $fallback if defined $fallback;
    return \%overloads_to_add;
}

sub _create_fallback_validator {
    my($fallback, $fallback_set_in);

    return sub {
        unless (@_) {
            # no args, return current value
            return $fallback;
        }

        my($role_name, $value) = @_;
        if (defined($value) and !defined($fallback)) {
            $fallback = $value;
            $fallback_set_in = $role_name;
            return 1;
        }
        return 1 unless (defined($fallback) and defined ($value));
        return 1 unless ($fallback xor $value);

        Carp::croak(sprintf(q(Cannot compose role %s: fallback value '%s' conflicts with fallback value '%s' in role %s),
                                $role_name,
                                $value ? $value : defined($value) ? 'FALSE' : 'UNDEF',
                                $fallback ? $fallback : defined($fallback) ? 'FALSE' : 'UNDEF',
                                $fallback_set_in));
    };
}


sub _collect_meta_properties_from_roles {
    my($desc, @role_objs) = @_;

    my(%meta_properties_to_add, %source_for_meta_properties_to_add);
    foreach my $role ( @role_objs ) {
        foreach my $meta_prop_name ( $role->meta_properties_to_compose_into_classes ) {
            next if (defined $desc->{$meta_prop_name} and $meta_prop_name ne 'valid_signals');
            next unless defined $role->$meta_prop_name;

            if ($meta_prop_name ne 'valid_signals') {
                if (exists $meta_properties_to_add{$meta_prop_name}) {
                    Carp::croak(sprintf(q(Cannot compose role %s: Meta property '%s' conflicts with meta property from role %s),
                                        $role->role_name,
                                        $meta_prop_name,
                                        $source_for_meta_properties_to_add{$meta_prop_name}));
                }
                $meta_properties_to_add{$meta_prop_name} = $role->$meta_prop_name;
                $source_for_meta_properties_to_add{$meta_prop_name} = $role->role_name;
            } else {
                $meta_properties_to_add{valid_signals} ||= [];
                push @{ $meta_properties_to_add{valid_signals} }, @{ $role->valid_signals };
            }
        }
    }
    return \%meta_properties_to_add;
}

sub _validate_role_requirements {
    my($class, $desc) = @_;

    my $class_name = $desc->{class_name};
    my %found_properties_and_methods = map { $_ => 1 } keys %{ $desc->{has} };

    foreach my $role_name ( @{ $desc->{roles} } ) {
        my $role = $class->get($role_name);
        foreach my $requirement ( @{ $role->requires } ) {
            unless ($found_properties_and_methods{ $requirement }
                        ||= _class_desc_lineage_has_method_or_property($desc, $requirement))
            {
                my $role_name = $role->role_name;
                Carp::croak("Cannot compose role $role_name: missing required property or method '$requirement'");
            }
        }

        # Properties and methods from this role can satisfy requirements for later roles
        foreach my $name ( $role->property_names, $role->method_names ) {
            $found_properties_and_methods{$name} = 1;
        }
    }

    return 1;
}

sub _validate_role_exclusions {
    my($class, $desc) = @_;

    my %role_names = map { $_ => $_ } @{ $desc->{roles} };
    foreach my $role ( map { $class->get($_) } @{ $desc->{roles} } ) {

        my @conflicts = grep { defined }
                            @role_names{ @{ $role->excludes } };
        if (@conflicts) {
            my $class_name = $desc->{class_name};
            my $plural = @conflicts > 1 ? 's' : '';
            Carp::croak(sprintf('Cannot compose role%s %s into class %s: Role %s excludes %s',
                                $plural,
                                join(', ', @conflicts),
                                $desc->{class_name},
                                $role->role_name,
                                $plural ? 'them' : 'it'));
        }
    }
    return 1;
}

sub _class_desc_lineage_has_method_or_property {
    my($desc, $requirement) = @_;

    my $class_name = $desc->{class_name};
    if (my $can = $class_name->can($requirement)) {
        return $can;
    }

    my @is = @{ $desc->{is} };
    my %seen;
    while(my $parent = shift @is) {
        next if $seen{$parent}++;

        if (my $can = $parent->can($requirement)) {
            return $can;
        }

        my $parent_meta = $parent->__meta__;
        if (my $prop_meta = $parent_meta->property($requirement)) {
            return $prop_meta;
        }
    }
    return;
}

sub _import_methods_from_roles_into_namespace {
    my($class_name, $roles) = @_;

    my $this_class_methods = UR::Util::coderefs_for_package($class_name);

    my(%all_imported_methods, %method_sources);
    foreach my $role ( @$roles ) {
        my $this_role_methods = $role->methods;
        my @this_role_method_names = keys( %$this_role_methods );

        my @class_failed_to_override = grep { ! _coderef_overrides_package($this_class_methods->{$_}, $role->role_name) }
                                       grep { exists $this_class_methods->{$_} }
                                       @this_role_method_names;
        if (@class_failed_to_override) {
            my $plural = scalar(@class_failed_to_override) > 1 ? 's' : '';
            my $conflicts = scalar(@class_failed_to_override) > 1 ? 'conflict' : 'conflicts';
            Carp::croak('Cannot compose role ' . $role->role_name
                        . ": method${plural} $conflicts with methods defined in the class.  "
                        . "Did you forget to add the 'overrides' attribute?\n\t"
                        . join(', ', @class_failed_to_override));
        }

        my @conflicting = grep { ! exists($this_class_methods->{$_}) }  # not a conflict if the class overrides
                          grep { exists $all_imported_methods{$_} }
                          @this_role_method_names;

        if (@conflicting) {
            my $plural = scalar(@conflicting) > 1 ? 's' : '';
            Carp::croak('Cannot compose role ', $role->role_name
                        . ": method${plural} conflicts with those defined in other roles\n\t"
                        . join("\n\t", join('::', map { ( $method_sources{$_}, $_ ) } @conflicting))
                        . "\n");
        }

        @method_sources{ @this_role_method_names } = ($role->role_name) x @this_role_method_names;
        @all_imported_methods{ @this_role_method_names } = @$this_role_methods{ @this_role_method_names };
    }

    delete @all_imported_methods{ keys %$this_class_methods };  # Don't import roles' methods already defined on the class
    foreach my $name ( keys %all_imported_methods ) {
        Sub::Install::install_sub({
            code => $all_imported_methods{$name},
            as => $name,
            into => $class_name,
        });
    }
}

sub _coderef_overrides_package {
    my($coderef, $package) = @_;

    my @overrides = UR::AttributeHandlers::get_overrides_for_coderef($coderef);
    return any { $_ eq $package } @overrides;
}

sub _apply_overloads_to_namespace {
    my($class_name, $overloads) = @_;

    my(%cooked_overloads);
    while( my($op, $impl) = each %$overloads) {
        $cooked_overloads{$op} = ref $impl
                                    ? sprintf(q($overloads->{'%s'}), $op)
                                    : qq('$impl');
    }

    my $string = "package $class_name;\n"
                 . 'use overload '
                 . join(",\n\t", map { sprintf(q('%s' => %s), $_, $cooked_overloads{$_}) } keys %cooked_overloads)
                 . ';';

    my $exception;
    do {
        local $@;
        eval $string;
        $exception = $@;
    };

    if ($exception) {
        Carp::croak("Failed to apply overloads to package $class_name: $exception");
    }
    return 1;
}

sub _define_role {
    my($role_name, $func, @params) = @_;

    if (defined($func) and $func eq "role" and @params > 1 and $role_name ne "UR::Role") {
        my @role_params;
        if (@params == 2 and ref($params[1]) eq 'HASH') {
            @role_params = %{ $params[1] };
        }
        elsif (@params == 2 and ref($params[1]) eq 'ARRAY') {
            @role_params = @{ $params[1] };
        }
        else {
            @role_params = @params[1..$#params];
        }
        my $role = UR::Role->define(role_name => $role_name, @role_params);
        unless ($role) {
            Carp::croak "error defining role $role_name!";
        }
        return sub { $role_name };
    } else {
        return;
    }
}

sub defer($) {
    Carp::croak('defer takes only a single argument') unless (@_ == 1);
    return UR::Role::DeferredValue->create(id => shift);
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
      excludes => ['Bad::Role'],
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
them.  A Role can require any composing class to implement a list of methods
or properties.

Roles are not classes.  They can not be instantiated or inherited from.  They
are composed into a class by listing their names in the C<roles> attribute of
a class definition.

=head2 Defining a Role

Roles are defined with the C<role> keyword.  Their definition looks very
similar to a class definition as described in L<UR::Object::Type::Initializer>.
In particular, Roles have a C<has> section to define properties, and accept
many class-meta attributes such as 'id_generator', 'valid_signals', and 'doc'.

Roles may implement operator overloading via the 'use overload' mechanism.

Roles also have unique atributes to declare restrictions on their use.

=over 4

=item requires

A listref of property and method names that must appear in any class composing
the Role.  Properties and methods defined in other roles or parent classes
can satisfy a requirement.

=item excludes

A listref of Role names that may not be composed together with this Role.
This is useful to declare incompatibilities between roles.

=back

=head2 Composing a Role

Compose one or more Roles into a class using the 'roles' attribute in a class
definition.

  class My::Class {
      roles => ['My::Role', 'Other::Role'],
      is => ['Parent::Class'],
      has => ['prop_a','prop_b'],
  };

Properties and meta-attributes from the Roles get copied into the composing
class.  Subroutines defined in the Roles' namespaces are imported into the
class's namespace.  Operator overloads defined in the Roles are applied to
the class.

=head3 Property and meta-attribute conflicts

An exception is thrown if multiple Roles are composed together that define
the same property, even if the composing class defines the same property in
an attempt to override them.

=head3 Method conflicts

An exception is thrown if multiple Roles are composed together that
define the same subroutine, or if the composing class defines the same
subroutine as any of the roles.

If the class wants to override a subroutine defined in one of its roles,
the override must be declared with the "Overload" attribute.

  sub overridden_method : Overrides(My::Role, Other::Role) { ... }

All the conflicting role names must be listed in the override, separated by
commas.  The class woll probably implement whatever behavior is required,
maybe by calling one role's method or the other, both methods, neither,
or anything else.

To call a function in a role, the function's fully qualified name, including
the role's package, must be used.

=head3 Overload conflicts

Like with method conflicts, an exception is thrown if multiple Roles are
composed together that overload the same operator unless the composing
class also overloads that same operator.

An exception is also thrown if composed roles define incompatible 'fallback'
behavior.  If a role does not specify 'fallback', or explicity sets it to
C<undef>, it is compatible with other values.  A Role that sets its 'fallback'
value to true or false is only compatible with other roles' values of undef
or the same true or false value.

=head2 __import__

Each time a Role is composed into a class, its C<__import__()> method is
called.  C<__import__()> is passed two arguments:

=over 4

=item *

The name of the role

=item *

The class metadata object composing the role.

=back

This happens after the class is completely constructed.

=head2 Deferred Values

A Role definition may contain L<UR::Role::DeferredValue> objects to act as
placeholders for values to be filled in when the role is composed into a
class.  These values are resolved at composition time by calling the named
function on the composing class.  For example:

  use UR::Role;
  role ObjectDisplayer {
      has => [
          target_object => { is => defer 'target_type' },
      ]
  };

  class ShowCars {
      roles => ['ObjectDisplayer'],
  };
  sub ShowCars::target_type { 'Car' }

When the 'target_object' property is composed into the ShowCars class, the
system calls the method C<ShowCars-E<gt>target_type()> to obtain the value
'Car' for the data_type of property 'target_object'.

UR::Role exports the function C<defer> to create these DeferredValue objects.

=head1 SEE ALSO

L<UR>, L<UR::Object::Type::Initializer>, L<UR::Role::DeferredValue>

=cut
