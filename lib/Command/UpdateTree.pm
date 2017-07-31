package Command::UpdateTree;

use strict;
use warnings 'FATAL';

class Command::UpdateTree {
    is => 'Command::Tree',
    doc => 'CRUD update tree class.',
};

sub sub_command_sort_position { .3 };

1;
