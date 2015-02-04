package Testing::Color;

use strict;
use Testing;

class Testing::Color {
    id_by => 'color_name',
    has => [qw( redness greenness blueness ) ],
};

1;
