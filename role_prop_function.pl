# Parameterised roles where the parameters are implemented as a function
# that returns an object with methods corresponding to the parameters of
# the composed role.
#
# Declaring a role creates a Role Prototype (similar to how declaring a class
# creates a Class meta-object).  A role creates a constructor function with
# the same name as the role's package that return a Role Instance.  This Role
# Instance represents a Role Prototype being consumed to one particular Class
# with a set of parameters.
#
# Before the role is consumed, the value returned by the method call is a
# placeholder object that knows what method was called of it.
#
# When the role is composed into a class, the role's parameters are bound to
# one particular instance of the role.  The role definition is scanned for
# placeholder objects and replaced with the actual parameter values.  The
# role_prop() function in the role's namespace is replaced by a function
# that can search the call stack for the closest function call with an
# invocant that consumed the role, and returns the proper value for the
# requested attribute.

package My::Role;

use UR::Role;  # exports role_prop() function

role My::Role {
    has => [
        role_param => { is => role_prop->data_type, doc => 'blah blah blah' },
    ],
};

sub print_role_param_type {
    print "role_param type is " . role_prop->data_type . "\n";
}

package My::Class;

class My::Class {
    roles => My::Role(data_type => 'Some::Data::Type'),
};

package Your::Class;

class Your::Class {
    roles => My::Role(data_type => 'Other::Data::Type'),
}

package main;

my $my_param_value = Some::Data::Type->create();
my $my_obj = My::Class->Create(role_param => $my_param_value);
$my_obj->print_role_param_type(); # prints "role_param type is Some::Data::Type"

my $your_param_value = Other::Data::Type->create();
my $your_obj = Your::Class->create(role_param => $your_param_value);
$your_obj->print_role_param_type(); # prints "role_param type is Other::Data::Type"

