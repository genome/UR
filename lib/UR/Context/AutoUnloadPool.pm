package UR::Context::AutoUnloadPool;

use strict;
use warnings;

require UR;
our $VERSION = "0.43"; # UR $VERSION

# These are plain Perl objects that get garbage collected in the normal way,
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

=pod

=head1 NAME

UR::Context::AutoUnloadPool - Automaticaly unload objects when scope ends

=head1 SYNOPSIS

  my $not_unloaded = Some::Class->get(...);
  do {
    my $guard = UR::Context::AutoUnloadPool->create();
    my $object = Some::Class->get(...);  # load an object from the database
    ...                                  # load more things
  };  # $guard goes out of scope - unloads objects

=head1 DESCRIPTION

UR Objects retrieved from the database normally live in the object cache for
the life of the program.  When a UR::Context::AutoUnloadPool is instantiated,
it tracks every object loaded during its life.  The Pool's destructor calls
unload() on those objects.

Changed objects and objects loaded before before the Pool is created will not
get unloaded.

=head1 METHODS

=over 4

=item create

  my $guard = UR::Context::AutoUnloadPool->create();

Creates a Pool object.  All UR Objects loaded from the database during this
object's lifetime will get unloaded when the Pool goes out of scope.

=item delete

  $guard->delete();

Invalidates the Pool object.  No objects are unloaded.  When the Pool later
goes out of scope, no objects will be unloaded.

=back

=head1 SEE ALSO

UR::Object, UR::Context

=cut
