package UR::Service::WebServer::Server;

use base 'HTTP::Server::PSGI';

# Override new because the default constructor doesn't accept a 'port' argument of
# undef to make the system pick a port
sub new {
    my($class, %args) = @_;

    my %supplied_port_arg;
    if (exists $args{port}) {
        $supplied_port_arg{port} = delete $args{port};
    }

    my $self = $class->SUPER::new(%args);
    if (%supplied_port_arg) {
        $self->{port} = $supplied_port_arg{port};
    }
    return $self;
}

sub listen_sock {
    return shift->{listen_sock};
}

1;


