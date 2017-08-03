package Command::Delete;

use strict;
use warnings 'FATAL';

class Command::Delete {
    is => 'Command::V2',
    is_abstract => 1,
    has_constant => {
        target_name_ub => { via => 'namespace', to => 'target_name_ub', },
    },
    doc => 'CRUD delete command class.',
};

sub help_brief { $_[0]->__meta__->doc }
sub help_detail { $_[0]->__meta__->doc }

sub execute {
    my $self = shift;

    my $target_name_ub = $self->target_name_ub;
    my $obj = $self->$target_name_ub;
    $self->status_message('Deleting %s', $obj->__display_name__);
    $obj->delete;

    1;
}

1;
