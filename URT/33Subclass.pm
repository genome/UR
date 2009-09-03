
package URT::33Subclass;

use strict;
use warnings;
## dont "use URT::33Baseclass";

class URT::33Subclass {
    isa => 'URT::33Baseclass',
    is_transactional => 0,
    has => [
        some_other_stuff => { is => 'SCALAR' },
        abcdefg => { }
    ]
};

sub create {
    my $class = shift;

    my $self = $class->SUPER::create(
        thingy => URT::Thingy->create
    );

    return $self;
}

1;

