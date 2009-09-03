
package URT::33Baseclass;

use strict;
use warnings;

class URT::33Baseclass {
    is_transactional => 0,
    has => [
        parent => { is => 'URT::33Subclass', id_by => 'parent_id' },
        thingy => { is => 'URT::Thingy', id_by => 'thingy_id' }
    ]
};

1;

