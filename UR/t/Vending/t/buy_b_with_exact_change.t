use strict;
use warnings;

use Test::More tests => 10;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";
use Vending;

my $machine = Vending::Machine->get();
ok($machine, 'Got the Vending::Machine instance');

# Stock the machine so there's something to get
my $prod = Vending::Product->create(name => 'Apple', manufacturer => 'Acme', cost_cents => 100);
ok($prod, 'Created a product type Apple');
my $slot = Vending::MachineLocation->get(name => 'b');
ok($slot, 'Got object for slot b');
my $item = $slot->add_item(subtype_name => 'Vending::Merchandise', product_id => $prod);
ok($item, 'Added an Apple inventory item to slot b');


ok($machine->insert('quarter'), 'Inserted a quarter');
ok($machine->insert('quarter'), 'Inserted a quarter');
ok($machine->insert('quarter'), 'Inserted a quarter');
ok($machine->insert('quarter'), 'Inserted a quarter');

my @items = $machine->buy('b');
is(scalar(@items), 1, 'Got back one item');
is($items[0]->name, 'Apple', 'It was an Apple');



