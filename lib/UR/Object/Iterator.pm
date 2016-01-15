package UR::Object::Iterator;

use strict;
use warnings;
require UR;
our $VERSION = "0.44"; # UR $VERSION;

our @CARP_NOT = qw( UR::Object );

# These are no longer UR Objects.  They're regular blessed references that
# get garbage collected in the regular ways

sub create {
    die "Don't call UR::Object::Iterator->create(), use create_for_filter_rule() instead";
}

sub create_for_filter_rule {
    my $class = shift;
    my $filter_rule = shift;
   

    my $code = $UR::Context::current->get_objects_for_class_and_rule($filter_rule->subject_class_name,$filter_rule,undef,1);
    
    my $self = bless { filter_rule_id => $filter_rule->id,
                       _iteration_closure => $code},
               __PACKAGE__;
    return $self;
}

sub create_for_list {
    my $class = shift;
    my $items = \@_;

    my $code = sub {
        shift @$items;
    };
    my $self = bless { _iteration_closure => $code }, $class;
    return $self;
}

sub map($&) {
    my($self, $mapper) = @_;

    my $wrapper = sub {
        local $_ = $self->next;
        defined($_) ? $mapper->() : $_;
    };

    return bless { _iteration_closure => $wrapper }, ref($self);
}


sub _iteration_closure {
    my $self = shift;
    if (@_) {
        return $self->{_iteration_closure} = shift;
    }
    $self->{_iteration_closure};
}


sub peek {
    my $self = shift;
    unless (exists $self->{peek_value}) {
        $self->{peek_value} = $self->{_iteration_closure}->();
    }
    $self->{peek_value};
}


sub next {
    my $self = shift;
    if (exists $self->{peek_value}) {
        delete $self->{peek_value};
    } else {
        $self->{_iteration_closure}->(@_);
    }
}

sub remaining {
    my $self = shift;
    my @remaining;
    while (defined(my $o = $self->next )) {
        push @remaining, $o;
    }
    @remaining;
}

1;

=pod

=head1 NAME

UR::Object::Iterator - API for iterating through objects matching a rule

=head1 SYNOPSIS

  my $rule = UR::BoolExpr->resolve('Some::Class', foo => 1);
  my $iter = UR::Object::Iterator->create_for_filter_rule($rule);
  while (my $obj = $iter->next()) {
      print "Got an object: ",$obj->id,"\n";
  }

  # Equivalent
  my $iter2 = Some::Class->create_iterator(foo => 1);
  while (my $obj = $iter2->next()) {
      print "Got an object: ",$obj->id,"\n";
  }

=head1 DESCRIPTION

get(), implemented in UR::Object, is the usual way for retrieving sets of
objects matching particular properties.  When the result set of data is
large, it is often more efficient to use an iterator to access the data 
instead of getting it all in one list.

UR::Object implements create_iterator(), which is just a wrapper around
create_for_filter_rule().

UR::Object::Iterator instances are normal Perl object references, not
UR-based objects.  They do not live in the Context's object cache, and
obey the normal Perl rules about scoping.

=head1 METHODS

=over 4

=item create_for_filter_rule

  $iter = UR::Object::Iterator->create_for_filter_rule($boolexpr);

Creates an iterator object based on the given BoolExpr (rule).  Under the
hood, it calls get_objects_for_class_and_rule() on the current Context
with the $return_closure flag set to true.

=item create_for_listref

  $iter = UR::Object::Iterator->create_for_listref( [ $obj1, $obj2, ... ] );

Creates an iterator based on objects contained in the given listref.

=item map

  $new_iter = $iter->map(sub { $_ + 1 });

Creates a new iterator based on an existing iterator.  Values returned by this
new iterator are based on the values of the existing iterator after going
through a mapping function.  This new iterator will  be exhausted when the
original iterator is exhausted.

=item next

  $obj = $iter->next();

Return the next object matching the iterator's rule.  When there are no more
matching objects, it returns undef.

=item peek

  $obj = $iter->peek();

Return the next object matching the iterator's rule without removing it.  The
next call to peek() or next() will return the same object.  Returns undef if
there are no more matching objects.

This is useful to test whether a newly created iterator matched anything.

=item remaining

  @objs = $iter->remaining();

Return a list of all the objects remaining in the iterator.  The list will be
empty if there are no more matching objects.

=back

=head1 SEE ALSO

UR::Object, UR::Context

=cut
