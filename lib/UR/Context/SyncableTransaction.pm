package UR::Context::SyncableTransaction;

use strict;
use warnings;

require UR;
our $VERSION = "0.43"; # UR $VERSION

use Carp;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Context::Transaction',
    has_constant_calculated => [
        _change_summary_data => { is => 'HASH',
                                  doc => 'mapping of class+id to a hash of property name + new value',
                                  calculate => '$self->_build_change_summary_data',
                                },
    ],
);

sub _build_change_summary_data {
    my $self = shift;

    my @changes = $self->get_changes();

    my $data = {};
    foreach my $change ( @changes ) {
        my($class_name, $id, $aspect) = map { $change->$_ } qw(changed_class_name changed_id changed_aspect);
        if ($aspect eq 'create') {
            $data->{'++created++'}->{$class_name}->{$id} = undef;
            delete $data->{'++deleted++'}->{$id};
        } elsif ($aspect eq 'delete') {
            $data->{'++deleted++'}->{$class_name}->{$id} = undef;
            delete $data->{'++created++'}->{$id};
        }
            
        next unless $class_name->__meta__->property_meta_for_name($aspect);

        my $obj = $class_name->get($id);
        $data->{$class_name}->{$id}->{$aspect} = $obj->$aspect;
    }
    return $data;
}

sub _change_summary_data_for_saving_object {
    my($self, $object) = @_;
    my $change_data = $self->_change_summary_data();

    my($class, $id) = ($object->class, $object->id);

    if ($change_data->{'++created++'}->{$class}->{$id}) {
        return ('insert', undef);

    } elsif ($change_data->{'++deleted++'}->{$class}->{$id}) {
        return ('delete', undef);

    } else {
        return ('update', $change_data->{$class}->{$id});
    }
}

sub commit {
    my $self = shift;

    $self->UR::Context::commit();
    $self->SUPER::commit();
    $self->__invalidate_change_summary_data__();
}

sub _get_changed_objects_for_sync_databases {
    my $self = shift;
    my $change_data = $self->_change_summary_data;

    my @objects;
    foreach my $class ( keys %$change_data ) {
        next if $class =~ m/\+\+/;  # skip ++created++ and ++deleted++
        my @ids = keys %{ $change_data->{$class} };
        push @objects, $class->get(\@ids);
    }

    my $created = $change_data->{'++created++'};
    foreach my $class ( keys %$created ) {
$DB::single=1;
        my @ids = keys %{ $created->{$class} };
        push @objects, $class->get(\@ids);
    }

    my $deleted = $change_data->{'++deleted++'};
    foreach my $class ( keys %$deleted ) {
        my $ghost_class = $class->ghost_class;
        my @ids = keys %{ $deleted->{$class} };
        push @objects, $ghost_class->get(\@ids);
    }

    return @objects;
}

sub _after_commit {
    # clean up change_counts for objects
    my $self = shift;

    my $change_data = $self->_change_summary_data;
    my($created, $deleted) = @$change_data{'++created++', '++deleted++'};

    foreach my $obj ( $self->_get_changed_objects_for_sync_databases ) {
        my($class, $id) = ($obj->class, $obj->id);
        if ($created->{$class}->{$id}
            or
            $deleted->{$class}->{$id}
        ) {
            delete $obj->{_change_count};

        } else {
            $obj->{_change_count} -= values %{$change_data->{$class}->{$id}};
        }
    }
}

1;
