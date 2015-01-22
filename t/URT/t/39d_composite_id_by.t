use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;
use Test::More tests => 3;

# Test that an id-by property using a composite ID for its value can refer
# to a class with multuple ID properties.
#
# Normally this isn't a problem since most classes compose composite IDs
# with join().  Passing in a single, composite ID to the composer returns
# back the same composite value.   Some classes have custom ID compositers
# (such as UR::Value::JSON) that require multiple values to be passed in
# to their ID compositers, and return a garbage value if a single, already-
# composite ID is passed in.

class Person {
    id_by => ['first_name','last_name'],
};
Person->__meta__->{'get_composite_id_resolver'} = sub {
    return join(':', map { $_ => shift } qw(first_name last_name));
};

class Thing {
    has => [
        owner => { is => 'Person', id_by => 'owner_id' },
    ],
};

my $person = Person->create(first_name => 'Bob', last_name => 'Smith');
ok($person, 'Create Person with multiple ID properties');

my $thing = Thing->create(owner_id => $person->id);
ok($thing, 'Create Thing with owner_id');

is($thing->owner, $person, "Thing's owner object is the Person object");
