package URT::ObjWithHash;

use warnings;
use strict;

use URT;
class URT::ObjWithHash {
    has => [
        myhash1 => { is => 'HASH' },
        myhash2 => { is => 'Hash' },
    ],
};

1;

