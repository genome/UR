
use strict;
use warnings;
use above "URT";
use Test::More tests => 7;

class Animal {
    has => [
        limbs => { is_many => 1, is => 'Animal::Limb', reverse_id_by => 'animal', is_mutable => 1 },
        fur => { is => 'Text' },
    ]
};

class Animal::Limb {
    id_by => [
        animal => { is => 'Animal', id_by => 'animal_id' },
        number => { is => 'Number' },
    ]
};

# make an example object
my $a = Animal->create();
ok($a, 'new animal');
# add parts the hard way
my $i1 = $a->add_limb(number => 1);
ok ($i1, 'has one foot.');
my $i2 = $a->add_limb(number => 2);
ok ($i2, 'has two feet!');

# make another, and add them in a slightly easier way
my $a2 = Animal->create(
    limbs => [
        { number => 1 },
        { number => 2 },
        { number => 3 },
        { number => 4 }, 
    ],
    fur => "fluffy",
);
ok($a2, 'yet another animal');
my @i = $a2->limbs();
is(scalar(@i),4, 'expected 4 feet!');

# make a third object, and add them the easiest way 
my $a3 = Animal->create(
    limbs => [1,2,3,4],
    fur => "fluffy",
);
ok($a3, 'more animals');
my @i2= $a3->limbs();
is(scalar(@i2),4, '4 feet again, the easy way');

