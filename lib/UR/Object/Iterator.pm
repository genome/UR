package UR::Object::Iterator;

use strict;
use warnings;
require UR;
our $VERSION = "0.39"; # UR $VERSION;

our @CARP_NOT = qw( UR::Object );

# These are no longer UR Objects.  They're regular blessed references that
# get garbage collected in the regular ways

#use UR;
#
#UR::Object::Type->define(
#    class_name      => __PACKAGE__,
#    has => [
#        filter_rule_id          => {},
#    ],
#);
#
#sub create_for_filter_rule {
#    my $class = shift;
#    my $filter_rule = shift;
#    my $code = $UR::Context::current->get_objects_for_class_and_rule($filter_rule->subject_class_name,$filter_rule,undef,1);
#    
#    my $self = $class->SUPER::create(
#        # TODO: some bug with frozen items?
#        filter_rule_id      => $filter_rule->id,        
#    );
#    
#    $self->_iteration_closure($code);    
#    return $self;
#}

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


sub _iteration_closure {
    my $self = shift;
    if (@_) {
        return $self->{_iteration_closure} = shift;
    }
    $self->{_iteration_closure};
}


sub next {
    shift->{_iteration_closure}->(@_);
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

=item next

  $obj = $iter->next();

Return the next object matching the iterator's rule.  When there are no more
matching objects, it returns undef.

=back

=head1 SEE ALSO

UR::Object, UR::Context

=cut
