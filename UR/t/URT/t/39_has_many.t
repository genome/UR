
use strict;
use warnings;
use above "URT";
use Test::More tests => 13;

class Animal {
    has => [
        fur => { is => 'Text' },
        
        # Two an indirect properties
        # referencing a single value 
        # via another object
        #  through a has-many
        # ..and they're writable.

        # one is to a regular property
        limbs => { is => 'Animal::Limb', reverse_id_by => 'animal', is_mutable => 1, is_many => 1 },
        foreleg_flexibility_score => { 
            via => 'limbs', 
            where => [ number => 1 ], 
            to => 'flexibility_score',
            is_mutable => 1,
        },
        
        # one is "to" an id property, 
        notes => { is => 'Animal::Note', reverse_id_by => 'animal', is_mutable => 1, is_many => 1 },
        primary_note_text   => { 
            via => 'notes', 
            where => [ type => 'primary' ],
            to => 'text', 
            is_mutable => 1 
        },
    ],
};

class Animal::Limb {
    id_by => [
        animal => { is => 'Animal', id_by => 'animal_id' },
        number => { is => 'Number' },
    ],
    has => [
        flexibility_score => { is => 'Number', is_optional => 1 },
    ]
};

class Animal::Note {
    id_by => [
        animal  => { is => 'Animal', id_by => 'animal_id' },
        type    => { is => 'Text' },
        text    => { is => 'Text' },
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
        { number => 1, flexibility_score => 11 },
        { number => 2, flexibility_score => 22 },
        { number => 3, flexibility_score => 33 },
        { number => 4, flexibility_score => 44 }, 
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

# indirect access..
my $note1 = $a3->add_note(type => 'primary', text => "note1");
ok($note1, "made a note");
my $note2 = $a3->add_note(type => 'secondary', text => "note2");
ok($note2, "made another note");
my $t = $a3->primary_note_text("note1b");
is($t,"note1b", "set a remote partial-id-value through the indirect accessor");
$t = $a3->primary_note_text();
is($t,"note1b","got back the partial-id-value through the indirect accessor");

my $s = $a3->foreleg_flexibility_score(100);
is($s,100,"set a remote non-id value through the indirect accessor");
$s = $a3->foreleg_flexibility_score();
is($s,100,"got back the non-id value through the indirect accessor");


