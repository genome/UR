# Parameterized roles where the parameters are implemented as variables within
# the role's package.  These variables are annotated with the RoleProperty
# attribute which registers them with the role composition machinery with the
# given name.
#
# Declaring a role creates a Role Prototype (similar to how declaring a class
# creates a Class meta-object).  A role creates a constructor function with
# the same name as the role's package that return a Role Instance.  This Role
# Instance represents a Role Prototype being consumed to one particular Class
# with a set of parameters.
#
# Before the role is consumed, the value of the variable is a placeholder
# object.
#
# When the role is composed into a class, the role's parameters are bound to
# one particular instance of the role.  The role definition is scanned for
# placeholder objects and replaced with the actual parameter values.  The
# variable's value is replaced by a tied object with "magic" functionality to
# determine which role instance by searching the call stack for the closest
# function call with an invocant that consumed the role and returning its
# parameter value.

package My::Role;

use UR::Role;
# Having to repeat the name in the attribute can be eliminated by using the
# PadWalker module
my $data_type : RoleProperty(data_type);

role My::Role {
    has => [
        role_param => { is => $data_type, doc => 'blah blah blah' },
    ],
};

sub print_role_param_type {
    print "role_param type is $data_type\n";
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
my $my_obj = My::Class->create(role_param => $my_param_value);
$my_obj->print_role_param_type(); # prints "role_param type is Some::Data::Type"

my $your_param_value = Other::Data::Type->create();
my $your_obj = Your::Class->create(role_param => $your_param_value);
$your_obj->print_role_param_type(); # prints "role_param type is Other::Data::Type"

