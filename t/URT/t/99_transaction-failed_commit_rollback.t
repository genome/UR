use strict;
use warnings;

use UR;
use IO::File;

use Test::More;

UR::Object::Type->define(
    class_name => 'Circle',
    has => [
        radius => {
            is => 'Number',
            default_value => 1,
        },
    ],
);


# Create a Circle
my $circle = Circle->create();
ok($circle->isa('Circle'), 'create a circle');
ok($circle->radius == 1, 'default radius is 1');


{
    my $transaction = UR::Context::Transaction->begin;
    isa_ok($transaction, 'UR::Context::Transaction');

    my $old_radius = $circle->radius;
    my $new_radius = $circle->radius + 5;
    isnt($circle->radius, $new_radius, "new circle radius isn't current radius");
    $circle->radius($new_radius);
    is($circle->radius, $new_radius, "circle radius changed to new radius");

    *Circle::__errors__ = sub {
        my $tag = UR::Object::Tag->create (
            type => 'invalid',
            properties => ['test_property'],
            desc => 'intentional error for test',
        );
        return ($tag);
    };

    is($transaction->commit, undef, 'commit failed');
    is($transaction->rollback, 1, 'rollback succeeded');
    is($circle->radius, $old_radius, 'circle radius was rolled back due to forced __errors__');
}


done_testing();

1;
