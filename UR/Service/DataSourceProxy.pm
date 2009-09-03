package UR::Service::DataSourceProxy;

use strict;
use warnings;

use UR;

UR::Object::Type->define(
    class_name => 'UR::Service::DataSourceProxy',
    is => 'UR::Object',
    properties => [
        host =>           { type => 'String',
                            is_transient => 1,
                            default_value => '0.0.0.0',
                            doc => 'The local address to listen on'},
        port =>           { type => 'String',
                            is_transient => 1,
                            default_value => 10293,
                           doc => 'The local port to listen on'},
        listen_socket =>  { type => 'IO::Socket',
                            is_transient => 1,
                            is_optional => 1,
                            doc => 'The listen socket'},
        all_select =>     { type => 'IO::Select',
                            is_transient => 1,
                            is_optional => 1,
                            doc => 'Select object for the listen socket and all the client sockets'},
        sockets_select => { type => 'IO::Select',
                            is_transient => 1,
                            is_optional => 1,
                            doc => 'Select object for just the client connected sockets'},
        use_sigio =>      { type => 'Boolean',
                            is_transient => 1,
                            default_value => 0,
                            doc => 'The program should use signals to handle requests automaticly' },
        sync_through =>   { type => 'Boolean',
                            is_transient => 1,
                            is_optional => 1,
                            default_value => 0,
                            doc => 'When a client syncs changes to us, automaticly do a sync_database to propogate changes to our data sources',
                          },
    ],
    id_by => ['host','port'],
    doc => 'An object to manage connections from other processes and appear as a data source to them',
);


# FIXME needs real pod docs.  In the mean time, here's how you'd create a program that's just
# a proxy server getting requests:
# use GSC;
# my $proxy = UR::Service::DataSourceProxy->create(host => '0.0.0.0', port => 10293);
# $proxy->process_messages(undef);

# For _read_message.  When the messaging is refactored, this wont't be needed
use UR::DataSource::RemoteCache;  

use IO::Socket;
use IO::Select;
use FreezeThaw;
use Time::HiRes;
use Fcntl;

sub create {
    my $class = shift;
    my %params = @_;

    my $obj = $class->SUPER::create(@_);

    return unless $obj;

    return $obj if ($obj->listen_socket);

    unless ($obj->_create_listen_socket()) {
        $class->error_message("Failed to create listen socket");
        return;
    }

    $obj->enable_sigio_processing(1) if ($obj->use_sigio);

    return $obj;
}


sub _listen_queue_size { 5;}


# FIXME This might work better as a UDP socket?
sub _create_listen_socket {
    my $self = shift;

    my $listen = IO::Socket::INET->new(LocalHost => $self->host,
                                       LocalPort => $self->port,
                                       Listen    => $self->_listen_queue_size,
                                       ReuseAddr => 1);
    unless ($listen) {
        $self->error_message("Couldn't create socket: $!");
        return;
    }
    $self->listen_socket($listen);
    $self->all_select(IO::Select->new($listen));
    $self->sockets_select(IO::Select->new());

    return 1;
}

# Add the given socket to the list of connected clients.
# if socket is undef, it blocks waiting on an incoming connection 
sub accept_connection {
    my $self = shift;
    my $socket = shift;

    unless ($socket) {
        my $listen = $self->listen_socket;

        $socket = $listen->accept();
        unless ($socket) {
            $self->error_message("accept() failed: $!");
            return;
       }
    }

    $self->sockets_select->add($socket);
    $self->all_select->add($socket);
    $self->_enable_async_io_on_handle($socket) if ($self->use_sigio);

    return $socket;
}


sub close_connection {
    my $self = shift;
    my $socket = shift;

    unless ($self->sockets_select->exists($socket)) {
        $self->error_message("Passed-in socket is not on the list of connected clients");
        return;
    }

    $self->_disable_async_io_on_handle($socket) if ($self->use_sigio);
    $self->sockets_select->remove($socket);
    $self->all_select->remove($socket);
    $socket->close();
    return 1;
}


# process a message on the indicated socket.  If socket is undef,
# then process a single message out of the many that may be ready
# to read
sub process_message_from_client {
    my($self, $socket) = @_;

    # FIXME this always picks the first in the list; it's not fair
    $socket ||= ($self->sockets_select->can_read())[0];
    return unless $socket;

    my($string,$cmd) = UR::DataSource::RemoteCache::_read_message(undef, $socket);
    if ($cmd == -1) {  # The other end closed the socket
        $self->close_connection($socket);
        return 1;
    }

    # We only support get() for now - cmd == 1
    my($return_command_value, @results);

    if ($cmd == 1)  {
        # a remote get()
        my $rule = (FreezeThaw::thaw($string))[0]->[0];
        my $class = $rule->subject_class_name();
        @results = $class->get($rule);

        $return_command_value = $cmd | 128;  # High bit set means a result code
    } elsif ($cmd == 2) {
        # a remote sync_database()
        my($objects_by_class_name) = FreezeThaw::thaw($string);
        @results = $self->_merge_object_changes($objects_by_class_name);
        $return_command_value = $cmd | 128;
    } else {
        $self->error_message("Unknown command request ID $cmd");
        $return_command_value = 255;
    }
        
    my $encoded = '';
    if (@results) {
        $encoded = FreezeThaw::freeze(\@results);
    }
    $socket->print(pack("LL", length($encoded), $return_command_value), $encoded);

    return 1;
}


sub _merge_object_changes {
    my($self,$objects_by_class_name) = @_;

    my $return_value = 0;

$DB::single=1;
    eval {
        # FIXME this would be way cooler if we could lean on UR::Context::Transaction.  Before that could
        # work, we'd need some way to ask a prior transaction what an object's state is.  And while we're
        # at it, why not just get rid of the db_saved_uncommitted/db_committed nonsense and just use the
        # transaction for that

        # Pass 1 - make sure any of the proposed changes isn't a conflict with any of
        # our local changes
        
        foreach my $class_name ( keys %$objects_by_class_name ) {
            foreach my $their_obj ( @{$objects_by_class_name->{$class_name}} ) {
                my $their_id = $their_obj->id;

                my $my_obj;
                if ($their_obj->isa('UR::Object::Ghost')) {
                    my($my_class) = substr($class_name, 0, length($class_name) - 7);  # Remove ::Ghost
                    $my_obj = $my_class->get($their_id);
                    unless ($my_obj) {
                        $self->error_message("Rejecting commit from remote client.  Remotely deleted $class_name id $their_id does not exist locally as $my_class");
                        $return_value = 0;
                        return 0;
                    }
                } else {
                    $my_obj = $class_name->get($their_id);
                }

                if (! $my_obj && $their_obj->{'db_committed'}) {
                    $self->error_message("Rejecting commit from remote client.  $class_name id $their_id is new locally, but transmitted as changed");
                    $return_value = 0;
                    return 0;

                } elsif ($my_obj && $my_obj->changed()) {
                    # FIXME is it worth going through all the properties to see if they're compatible?
                    $self->error_message("Rejecting commit from remote client.  $class_name id $their_id is already changed");
                    $return_value = 0;
                    return 0;  

                } else {
                    $their_obj->{'__my_obj'} = $my_obj;
                }
            }
        }

        # Pass 2 - Apply changes to our transaction
        foreach my $class_name ( keys %$objects_by_class_name ) {
            foreach my $their_obj ( @{$objects_by_class_name->{$class_name}} ) {
                my @changes = $their_obj->changed;
                my @properties = map { $_->properties } @changes;   # Seems to be one Change for each changed property
                
                my $my_obj = $their_obj->{'__my_obj'};

                if ($their_obj->isa('UR::Object::Ghost')) {
                    $my_obj->delete();
               
                } elsif ($my_obj) {
                    foreach my $property ( @properties ) {
                        $my_obj->$property($their_obj->$property);
                    }

                } else {
                    my %create_params = map { ( $_, $their_obj->$_ ) } @properties;
                    $class_name->create(%create_params);
                }
            }
        }

        if ($self->sync_through) {
            $return_value = UR::Context->commit();
        } else {
            $return_value = 1;
        }
    };

    if ($@) {
        $self->error_message($@);
    }
    return ($return_value, $self->error_text());
}
                 


# go into a loop processing messages from all the connected sockets (and 
# the listen socket), for the given time period in seconds.  0 seconds
# means do one pass through all that are readable and return, undef
# means stay in the loop forever
#
# FIXME socket communication needs to be refactored out to some common location
# for example, the listen socket and client sockets can both implement
# process_message(), where the listen socket does what is accept_connection()
sub process_messages {
    my($self,$timeout) = @_;

    my $select = $self->all_select;

    my $start_time = Time::HiRes::time();

    SELECT_LOOP:
    while(1) {
        my @ready = $select->can_read($timeout);
        for (my $i = 0; $i < @ready; $i++) {
            if ($ready[$i] eq $self->listen_socket) {
                $self->accept_connection();
                # If we're running as a signal handler for sigio, and the client has already sent
                # data down the newly-connected socket before we can leave the handler, then we've
                # already lost the signal for that new data since it was masked.  This workaround
                # gives the above select() a chance to see the data being ready.
                next SELECT_LOOP;
            } else {
                $self->process_message_from_client($ready[$i]);
            }
        }
        last if(defined($timeout) && 
                    ( $timeout == 0 ||
                      (Time::HiRes::time() - $start_time > $timeout)
                    )
               );
    }

    return 1;
}


# FIXME There's a more efficient method of determining which handles 
# need attention during a sigio than select()ing.  See the manpage of
# fcntl(2) and the section on F_SETSIG and setting SA_SIGINFO.  Implement
# this later
# FIXME there should probably be a way to turn it off, too
sub enable_sigio_processing {
    my $self = shift;

    $self->use_sigio(1);
    my $prev_sigio_handler = $SIG{'IO'};
    
    # Step 1, set the closure for handling the signal
    $SIG{'IO'} = sub {
        $self->process_messages(0);
        return unless $prev_sigio_handler;
        $prev_sigio_handler->();
    };

    # Set up async IO stuff on all the active handles
    foreach my $fh ( $self->all_select->handles ) {
        $self->_enable_async_io_on_handle($fh);
    }
}
        

sub _enable_async_io_on_handle {
    my($self,$fh) = @_;

    # Set the pid for processing the signal (that would be us)
    # At one point, there was a bug in fcntl that could cause it to die
    # with a "Modification of a read-only value attempted" exception
    # if the F_SETOWN was right in fcntl()'s arg list.  I don't know if
    # or when the bug was fixed, but the workaround is to copy the constant
    # value into a mutable scalar first
    my $getowner = &Fcntl::F_GETOWN;
    my $prev_owner = fcntl($fh, $getowner,0);

    my $setowner = &Fcntl::F_SETOWN;
    #my $pid = $$;
    #$pid += 0;   # if $$ was ever used in string context, fcntl does the wrong thing with it.  This forces it back to numberic context
    unless (fcntl($fh, $setowner, $$ + 0)) {
        $self->error_message("fcntl F_SETOWN failed: $!");
        return;
    }

#    my $setsig = &Fcntl::F_SETSIG;
#    my $signum = 100;
#    unless (fcntl($fh, $setsig, $signum)) {
#       $self->error_message("fcntl F_SETSIG failed: $!");
#       return;
#    }

    # Enable the async IO flag
    my $flags = fcntl($fh, &Fcntl::F_GETFL,0);
    unless ($flags) {
        $self->error_message("fcntl F_GETFL failed: $!");
        fcntl($fh, $setowner, $prev_owner);
        return;
    }
    $flags |= &Fcntl::O_ASYNC;
    unless (fcntl($fh, &Fcntl::F_SETFL, $flags)) {
        $self->error_message("fcntl F_SETFL failed: $!");
        fcntl($fh, $setowner, $prev_owner);
        return;
    }

    return 1;
}

# This needs to be called when a handle closes or it'll generate an endless stream
# of signals to let us know that it's closed
sub _disable_async_io_on_handle {
    my($self,$fh) = @_;

    # I think it's good enough it just turn off the async flag, and not
    # have to reset the FH's owner
    my $flags = fcntl($fh, &Fcntl::F_GETFL,0);
    unless ($flags) {
        $self->error_message("fcntl F_GETFL failed: $!");
        return;
    }

    $flags &= ~(&Fcntl::O_ASYNC);
    unless (fcntl($fh, &Fcntl::F_SETFL, $flags)) {
        $self->error_message("fcntl F_SETFL failed: $!");
        return;
    }

    return 1;
}


1;
