use strict;
use warnings;

use above 'UR';
use Test::More;

package Car;

class Car {
    has => [
        make => {
            is => 'Text',
        },
    ],
};

sub make {
    my $self = shift;
    if (@_) {
        my $value = shift;
        $self->__make($value);
    }
    return $self->__make;
}

package main;

my $car = Car->create(make => 'GM');
isa_ok($car, 'Car');

my $observer_ran = 0;
$car->add_observer(
    aspect => 'make',
    callback => sub { $observer_ran = 1 },
);

is($observer_ran, 0, 'observer has not run yet');

$car->make('Ford');
is($car->make, 'Ford', 'make changed to Ford');

is($observer_ran, 1, 'observer triggered from make change');

done_testing();
