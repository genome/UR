package UR::Service::RPC::Server;

use UR;
use IO::Select;

use strict;
use warnings;

# We're going to be essentially reimplementing an Event queue here. :(

class UR::Service::RPC::Server {
    has => [
        'select' => { is => 'IO::Select' },
        timeout  => { is => 'Float', default_value => undef },
        executers  => { is => 'HASH', doc => 'maps file handles to the UR::Service::RPC::Executer objects we are working with' },
    ], 
};

sub create {
    my($class, %args) = @_;

    unless ($args{'executers'}) {
        $args{'executers'} = {};
    }
    
    unless ($args{'select'}) {
        my @fh = map { $_->fh } values %{$args{'executers'}};
        $args{'select'} = IO::Select->new(@fh);
    }

    my $self = $class->SUPER::create(%args);

    return $self;
}

sub add_executer {
    my($self,$executer,$fh) = @_;

    unless ($fh) {
        if ($executer->can('fh')) {
            $fh = $executer->fh;
        } else {
            $self->error_message("Cannot determine file handle for RPC executer $executer");
            return;
        }
    }

    $self->{'executers'}->{$fh} = $executer;
    $self->select->add($fh);
}

sub loop {
    my $self = shift;

    my $timeout;
    if (@_) {
        $timeout = shift;
    } else {
         $timeout = $self->timeout;
    }

    my @ready = $self->select->can_read($timeout);

    my $count = 0;
    foreach my $fh ( @ready ) {
        my $executer = $self->{'executers'}->{$fh};
        unless ($executer) {
            $self->error_message("Cannot determine RPC executer for file handle $fh fileno ",$fh->fileno);
            return;
        }

        $count++;
        unless ($executer->execute($self) ) {
            # they told us they were done
            $self->select->remove($fh);
            delete $self->{'executers'}->{$fh};
        }
    }

    return $count;
}

1;
