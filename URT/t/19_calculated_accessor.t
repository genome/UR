use warnings;
use strict;

use UR;
use Test::More tests => 12;

UR::Object::Type->define(
    class_name => 'Acme',
    is => ['UR::Namespace'],
);

UR::Object::Type->define(
    class_name => 'Acme::Employee',
    has => [
        first_name => { type => "String" },
        last_name => { type => "String" },
        full_name => { 
            calculate_from => ['first_name','last_name'], 
            calculate => '$first_name . " " . $last_name', 
        },
        user_name => {
            calculate_from => ['first_name','last_name'],
            calculate => 'lc(substr($first_name,0,1) . substr($last_name,0,5))',
        },
        email_address => { calculate_from => ['user_name'] },
    ]
);

sub Acme::Employee::email_address {
    my $self = shift;
    return $self->user_name . '@somewhere.tv';
}

my $e1 = Acme::Employee->create(first_name => "John", last_name => "Doe");
ok($e1, "created an employee object");

ok($e1->can("full_name"), "employees have a full name");
ok($e1->can("user_name"), "employees have a user_name");
ok($e1->can("email_address"), "employees have an email_address");

is($e1->full_name,"John Doe", "name check works");
is($e1->user_name, "jdoe", "user_name check works");
is($e1->email_address, 'jdoe@somewhere.tv', "email_address check works");

$e1->first_name("Jane");
$e1->last_name("Smitharoonie");

is($e1->full_name,"Jane Smitharoonie", "name check works after changes");
is($e1->user_name, "jsmith", "user_name check works after changes");
is($e1->email_address, 'jsmith@somewhere.tv', "email_address check works");

UR::Object::Type->define(
    class_name => "Acme::LineItem",
    has => [
        quantity    => { type => 'Number' },
        unit_price  => { type => 'Money'  },
        sub_total   => { type => 'Money', calculate => 'sum',
                            calculate_from => ['quantity','unit_price'] },
                            
    ],
);  

my $line = Acme::LineItem->create(quantity => 5, unit_price => 2);
ok($line, "made an order line item");
is($line->sub_total,7, "got the correct sub-total");


