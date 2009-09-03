package UR::Service::RPC::Executer;

use UR;

use strict;
use warnings;

class UR::Service::RPC::Executer {
    has => [
        fh => { is => 'IO::Handle', doc => 'handle we will send and receive messages across' },
    ],
    has_optional => [
        use_sigio => { is => 'Boolean', default_value => 0 },
    ],
    is_transactional => 0,
};


sub create {
    my $class = shift;

    my $obj = $class->SUPER::create(@_);
    return unless $obj;

    if ($obj->use_sigio) {
        UR::Service::RPC->enable_sigio_processing($obj);
    }

    $obj->create_subscription(method => 'use_sigio',
                              callback => sub {
                                  my ($changed_object, $changed_property, $old_value, $new_value) = @_;
                                  return 1 if ($old_value == $new_value);

                                  if ($new_value) {
                                      UR::Service::RPC->enable_sigio_processing($obj);
                                  } else {
                                      UR::Service::RPC->disable_sigio_processing($obj);
                                  }
                             });
    return $obj;
}


# sub classes can override this
# If they're going to reject the request, $msg should be modified in place
# with a return value and exception, because we'lre going to return it right back
# to the requester
sub authenticate {
#    my($self,$msg) = @_;
    return 1;
}

# Process one message off of the file handle
sub execute {
    my $self = shift;
    
    my $msg = UR::Service::RPC::Message->recv($self->fh);
    unless ($msg) {
        # The other end probably closed the socket
        $self->close_connection();
        return 1;
    }

    my $response;

    if ($self->authenticate($msg)) {

        my $target_class = $msg->target_class || ref($self);
        my $method = $msg->method_name;
        my @arglist = $msg->param_list;
        my $wantarray = $msg->wantarray;
        my %resp_msg_args = ( target_class => $target_class,
                              method_name  => $method,
                              params       => \@arglist,
                              'wantarray'  => $wantarray,
                              fh           => $self->fh );


        my $method_name = join('::',$target_class, $method);
        if ($wantarray) {
            my @retval;
            eval { no strict 'refs'; @retval = &{$method_name}(@arglist); };
            $resp_msg_args{'return_values'} = \@retval unless ($@);
        } elsif (defined $wantarray) {
            my $retval;
            eval { no strict 'refs'; $retval = &{$method_name}(@arglist); };
            $resp_msg_args{'return_values'} = [$retval] unless ($@);
        } else {
            eval { no strict 'refs'; &{$method_name}(@arglist); };
        }
        $resp_msg_args{'exception'} = $@ if $@;
        $response = UR::Service::RPC::Message->create(%resp_msg_args);

    } else {
        # didn't authenticate.
        $response = $msg;
    }

    unless ($response->send()) {
        $self->fh->close();
    }

    return 1;
}



sub close_connection {
    my $self = shift;
  
    $self->use_sigio(0);

    $self->fh->close();
}

 
1;

