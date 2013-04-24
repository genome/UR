package UR::Service::UrlRouter;

use strict;
use warnings;
use UR;

use Sub::Install;

use overload '&{}' => \&__call__,  # To support being called as a code ref
             'bool' => sub { 1 };  # Required due to an unless() test in UR::Context

class UR::Service::UrlRouter { };

foreach my $method ( qw( GET POST PUT DELETE ) ) {
    my $code = sub {
        my($self, $path, $sub) = @_;

        my $list = $self->{$method} ||= [];
        push @$list, [ $path, $sub ];
    };
    Sub::Install::install_sub({
        as => $method,
        code => $code,
    });
}

sub __call__ {
    my $self = shift;
    return sub {
        my $env = shift;

        my $req_method = $env->{REQUEST_METHOD};
        my $matchlist = $self->{$req_method} || [];

        foreach my $route ( @$matchlist ) {
            my($path,$cb) = @$route;
            my $call = sub {    my $rv = $cb->($env, @_);
                                return ref($rv) ? $rv : [ 200, [], [$rv] ];
                            };

            if (my $ref = ref($path)) {
                if ($ref eq 'Regexp' and (my @matches = $env->{PATH_INFO} =~ $path)) {
                    return $call->(@matches);
                } elsif ($ref eq 'CODE' and $path->($env)) {
                    return $call->();
                }
            } elsif ($env->{PATH_INFO} eq $path) {
                return $call->();
            }
        }
        return [ 404, [ 'Content-Type' => 'text/plain' ], [ 'Not Found' ] ];
    }
}

1;
