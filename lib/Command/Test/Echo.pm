use strict;
use warnings;
use UR;
use Command;

package Command::Test::Echo;

class Command::Test::Echo {
    is => 'Command',
    has => [
        in => { is => 'Text' },
        out => { is => 'Text', is_output => 1, is_optional => 1 },
    ]
};

sub execute {
    my $self = shift;
    for (1..6) {
        print $self->in,"\n";
        sleep 1;
    }
    if ($self->in =~ /fail/) {
        return;
    }
    elsif ($self->in =~ /die/) {
        die $self->in;
    }
    $self->out($self->in);
    return 1;
}

1;

