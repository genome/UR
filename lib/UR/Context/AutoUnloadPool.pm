package UR::Context::AutoUnloadPool;

use strict;
use warnings;

require UR;
our $VERSION = "0.43"; # UR $VERSION

# These are plan Perl objects that get garbage collected in the normal way,
# not UR::Objects

sub create {
    my $class = shift;
    my $self = bless { pool => {} }, $class;
    $self->_attach_observer();
    return $self;
}

sub delete {
    my $self = shift;
    delete $self->{pool};
    $self->_detach_observer();
}

sub _attach_observer {
    my $self = shift;
    Scalar::Util::weaken($self);
    my $o = UR::Object->add_observer(
                aspect => 'load',
                callback => sub {
                    my $loaded = shift;
                    $self->_object_was_loaded($loaded);
                }
            );
    $self->{observer} = $o;
}

sub _detach_observer {
    my $self = shift;
    delete($self->{observer})->delete();
}

sub _object_was_loaded {
    my($self, $o) = @_;
    $self->{pool}->{$o->class}->{$o->id} = undef;
}

sub _unload_objects {
    my $self = shift;
    return unless $self->{pool};

    my @unload_exceptions;
    foreach my $class_name ( keys %{$self->{pool}} ) {
        foreach ( $class_name->is_loaded([ keys %{$self->{pool}->{$class_name}} ] ) ) {
            unless (eval { $_->unload(); 1; } ) {
                push @unload_exceptions, $@;
            }
        }
    }
    die join("\n", 'The following exceptions happened while unloading:', @unload_exceptions) if @unload_exceptions;
}

sub DESTROY {
    local $@;

    my $self = shift;
    return unless ($self->{pool});
    $self->_detach_observer();
    $self->_unload_objects();
}

1;
