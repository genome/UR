# Using UR::Role exports a function deferred() which returns a dummy
# placeholder object.
#
# When the role is consumed, classes would be allowed to redefine a property
# declared in a role but would have to declare that it's either an override
# (completely replaces the role's property) or augments it (only the property
# keys mentioned in the class's definition override the keys in the role's
# definition), otherwise an exception is thrown.
#
# After role's properties are mixed in to the class, if any placeholders still
# exist, an exception is thrown, which forces the consuming class to provide
# values for all the deferred values.

package My::Role;

use UR::Role;  # exports deferred() function
role My::Role {
    has => [
        role_param => { is => deferred, doc => 'blah blah blah' },
    ],
};

package My::Class;

class My::Class {
    roles => 'My::Role',
    has => [
        role_param => { is => 'Some::Data::Type', augments => 'My::Role' },
    ],
};

package Your::Class;

class Your::Class {
    roles => 'My::Role',
    has => [
        role_param => { is => 'Other::Data::Type', augments => 'My::Role' },
    ],
}

package main;

my $my_param_value = Some::Data::Type->create();
my $my_obj = My::Class->create(role_param => $my_param_value);

my $your_param_value = Other::Data::Type->create();
my $your_obj = Your::Class->create(role_param => $your_param_value);



