package UR::Service::RPC::Message;

use UR;
use FreezeThaw;
use IO::Select;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => 'UR::Service::RPC::Message',
    has => [
        target_class => { is => 'String' },
        method_name  => { is => 'String' },
    ],
    has_optional => [
        #arg_list     => { is => 'ARRAY' },
        params     => { is => 'Object', is_many => 1 },
        return_values => { is => 'Object', is_many => 1 },
        'wantarray'  => { is => 'Integer' },
        fh           => { is => 'IO::Handle' },
        exception    => { is => 'String' },
    ],
    is_transactional => 0,
);


sub create {
    my($class,%params) = @_;

    foreach my $key ( 'params', 'return_values' ) {
        if (!$params{$key}) {
            $params{$key} = [];
        } elsif (ref($params{$key}) ne 'ARRAY') {
            $params{$key} = [ $params{$key} ];
        }
    }

    return $class->SUPER::create(%params);
}

    


sub send {
    my $self = shift;
    my $fh = shift;

    $fh ||= $self->fh;

    my %struct;
    foreach my $key ( qw (target_class method_name params wantarray return_values exception) ) {
         $struct{$key} = $self->{$key};
    }

    my $string = FreezeThaw::freeze(\%struct);
    $string = pack('N', length($string)) . $string;

    my $len = length($string);
    my $sent = 0;
    while($sent < $len) {
        my $wrote = $fh->syswrite($string, $len - $sent, $sent);

        if ($wrote) {
            $sent += $wrote;
        } else {
            # The filehandle closed for some reason
            $fh->close;
            return undef;
        }
    }

    return $sent;
}



sub recv {
    my($class, $fh, $timeout) = @_;

    # You can also call recv on a message object previously created
    if (ref($class) && $class->isa('UR::Service::RPC::Message')) {
        my $fh = $class->fh;
        $class = ref($class);
        return $class->recv($fh);
    }

    if (@_ < 3) {  # # if they didn't specify a timeout
        $timeout = 5; # Default wait 5 sec
    }

    my $select = IO::Select->new($fh);

    # read in the message len, 4 chars
    my $msglen;
    my $numchars = 0;
    while ($numchars < 4) {
        unless ($select->can_read($timeout)) {
            $class->warning_message("Can't get message length, timed out");
            return;
        }

        my $read = $fh->sysread($msglen, 4-$numchars, $numchars);

        unless ($read) {
            $class->warning_message("Can't get message length: $!");
            return;
        }

        $numchars += $read;
    }

    $msglen = unpack('N', $msglen);

    my $string = '';
    $numchars = 0;
    while ($numchars < $msglen) {
        unless ($select->can_read($timeout)) {
            $class->warning_message("Timed out reading message after $numchars bytes");
            return;
        }

        my $read = $fh->sysread($string, $msglen - $numchars, $numchars);

        unless($read) {
            $class->warning_message("Error reading message after $numchars bytes: $!");
            return;
        }

        $numchars += $read;
    }

    my($struct) = FreezeThaw::thaw($string);

    my $obj = $class->create(%$struct, fh => $fh);

    return $obj;
}
        
 

1;
