package UR::Role::DeferredValue;

use strict;
use warnings;

use Scalar::Util qw(blessed);

# Used in Role definitions to defer resolving to a concrete value until it
# is composed into a class.

class UR::Role::DeferredValue {
    id_by => [
        id => { is => 'Text' },
    ],
};
        

sub value_for {
    my($self, $class_name) = @_;
    my $param = $self->id;
    return $param eq 'class'
            ? $class_name # simulate $class_name->class() though the class bay not be functional yet
            : $class_name->$param;
}

sub search_for_deferred_values_in_struct {
    my($class, $struct) = @_;

    my @deferred;
    my $cb = sub {
        my $deferred_ref = shift;
        push @deferred, $$deferred_ref;
    };
    $class->visit_deferred_values_in_struct($struct, $cb);
    return @deferred;
}

sub apply_deferred_values_in_struct {
    my($class, $class_name, $struct) = @_;

    my $cb = sub {
        my $deferred_ref = shift;
        my $deferred = $$deferred_ref;
        $$deferred_ref = $deferred->value_for($class_name);
    };
    $class->visit_deferred_values_in_struct($struct, $cb);
}

sub visit_deferred_values_in_struct {
    my($class, $struct, $cb) = @_;

    return unless my $ref = ref($struct);
    if ($ref eq 'HASH') {
        foreach my $key ( keys %$struct ) {
            my $val = $struct->{$key};
            if (blessed($val) and $val->isa(__PACKAGE__)) {
                $cb->(\$struct->{$key});
            } else {
                $class->visit_deferred_values_in_struct($struct->{$key}, $cb);
            }
        }
    } elsif ($ref eq 'ARRAY') {
        for(my $i = 0; $i < @$struct; $i++) {
            my $val = $struct->[$i];
            if (blessed($val) and $val->isa(__PACKAGE__)) {
                $cb->(\$struct->[$i]);
            } else {
                $class->visit_deferred_values_in_struct($struct->[$i], $cb);
            }
        }
    } elsif ($ref eq 'SCALAR') {
        $class->visit_deferred_values_in_struct($$struct, $cb);
    }
}


1;

__END__

=pod

=head1 NAME

UR::Role::DeferredValue - Defer value to a class when composing a Role

=head1 SYNOPSIS

  package My::Role;
  use UR::Role;
  role My::Role {
      has => [
          role_property => { is => defer 'property_type', id_by => defer 'linking_id' },
      ],
  };

  package My::Class;
  class My::Class {
      roles => ['My::Role'],
  };
  sub property_type { 'Other::Class' }
  sub linking_id { 'other_class_id' }

=head1 DESCRIPTION

DeferredValues are placed into a Role definition when a value is required but
will not be known until it is composed into a class.  When the role is finally
used, the DeferredValue will be swapped out with the real value obtained by
calling the named method on the composing class.

In the SYNOPSIS example, the property definition for 'role_property' in class
MyClass will become

  role_property => { is => 'Other::Class', id_by => 'other_class_id' }.

=head1 SEE ALSO

L<UR::Role>

=cut

