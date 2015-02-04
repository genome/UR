package Testing::Something::SubClass2;
use strict;

class Testing::Something::SubClass2 {
    is => 'Testing::Something',
    has => [
        coolness => { is => 'Integer' },
    ],
};

sub cool_method {
  'a';
}

1;
