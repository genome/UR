#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 4;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT; # dummy namespace


my @events;

# A test datasource
package URT::DataSource::Testing;

class URT::DataSource::Testing {
    is => 'URT::DataSource::SomeSQLite'
};

sub disconnect {
    my $self = shift;
    push @events, 'method:disconnect';
    $self->SUPER::disconnect(@_);
}

sub create_default_handle {
    my $self = shift;
    push @events, 'method:create_default_handle';
    $self->SUPER::create_default_handle(@_);
}

*_init_created_dbh = \&init_created_handle;
sub init_created_handle {
    my $self = shift;
    push @events, 'method:init_created_handle';
    $self->SUPER::init_created_handle(@_);
}

foreach my $method ( qw(precreate_handle create_handle predisconnect_handle disconnect_handle ) ) {
    URT::DataSource::Testing->create_subscription(
        method => $method,
        callback => sub {
            my($self,$reported_method) = @_;
            push @events, "signal:$reported_method";
        }
    );
}

package main;

my $dbh = URT::DataSource::Testing->get_default_handle();
ok($dbh, 'get_default_handle()');

is_deeply(\@events,
    ['signal:precreate_handle', 'method:create_default_handle', 'signal:create_handle', 'method:init_created_handle'],
    'signals and methods called in the expected order');

@events = ();

ok(URT::DataSource::Testing->disconnect_default_handle(), 'disconnect_default_handle()');
is_deeply(\@events,
    ['signal:predisconnect_handle', 'method:disconnect', 'signal:disconnect_handle'],
    'signals and methods called in the expected order');

