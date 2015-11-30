package UR::Role;

use strict;
use warnings;

use UR;
use UR::Object::Type::InternalAPI;
use UR::Util;
use UR::AttributeHandlers;

use UR::Role::Param;
use UR::Role::Prototype;
use UR::Role::PrototypeWithParams;
use UR::Role::Instance;

use Scalar::Util qw(blessed);
use List::MoreUtils qw(any);
use Carp;
our @CARP_NOT = qw(UR::Object::Type);

our $VERSION = "0.44"; # UR $VERSION;;

Class::Autouse->sugar(\&_define_role);

sub define {
    my $class = shift;
    UR::Role::Prototype->define(@_);
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
        my $role = UR::Role::Prototype->define(role_name => $role_name, @role_params);
        unless ($role) {
            Carp::croak "error defining role $role_name!";
        }
        return sub { $role_name };
    } else {
        return;
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
define the same subroutine, or if the composing class (or any of its parent
classes) defines the same subroutine as any of the roles.

If the class wants to override a subroutine defined in one of its roles,
the override must be declared with the "Overrides" attribute.

  sub overridden_method : Overrides(My::Role, Other::Role) { ... }

All the conflicting role names must be listed in the override, separated by
commas.  The class will probably implement whatever behavior is required,
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

=head2 Parameterized Roles

Scalar variables with the C<RoleParam> attribute are designated as role
params.  Values can be supplied when a role composes the role as a means to
provide more flexibility and genericity for a role.

  package ObjectDisplayer;
  use ProjectNamespace;

  our $target_type : RoleParam(target_type);
  role ObjectDisplayer {
      has => [
          target_object => { is => $target_type },
      ],
  };

  package ShowCars;
  class ShowCars {
      roles => [ ObjectDisplayer->create(target_type => 'Car' ],
  };

When the role is composed, the call to C<create()> in the class definition
creates a L<UR::Role::Instance> to represent the ObjectDisplayer role being
composed into the ShowCars class with the params C<{ target_type => 'car' }>.
Values for the role param values in the role definition are swapped out with
the provided values as the role's properties are composed into the class.

At run-time, these role param variables are tied with the L<UR::Role::Param>
class.  Its C<FETCH> method searches the call stack for the first function
whose invocant composes the role where the variable's value is being fetched
from.  The proper param value is returned.

An exception is thrown if a class composes a role and either provides unknown
role params or omits values for existing params.

=head1 SEE ALSO

L<UR>, L<UR::Object::Type::Initializer>, L<UR::Role::Instance>, L<UR::Role::Param>

=cut
