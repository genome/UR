package UR::Object::Reference;

use strict;
use warnings;

no warnings;

sub get_property_links
{
    my $self = shift;
    my $id = $self->id;
    my @property_links =
        sort { $a->rank <=> $b->rank || $a->id cmp $b->id }
        UR::Object::Reference::Property->get(tha_id => $id);
    return @property_links;
}

sub delete
{
    my $self = shift;
    my @property_links = $self->get_property_links;
    for my $link (@property_links) {
        $link->delete;
    }
    return $self->SUPER::delete();
}


sub property_link_names {
    map { $_->property_name } shift->get_property_links(@_);
}

sub r_property_link_names {
    map { $_->r_property_name } shift->get_property_links(@_);
}

1;

=pod

=head1 NAME

UR::Object::Reference - Metadata about one class referring to another

=head1 SYNOPSIS

  my $classobj = Some::Class->__meta__;
  my @refs = $classobj->reference_metas;

  my $remote_class_obj = $refs[0]->r_class_meta;

=head1 DESCRIPTION

This class implements the infrastructure metadata about how classes are
linked to each other.  Whenever the class initializer encounters an 
indirect property, a Reference object is created to denote the classes
and properties involved in the link.

Instances of UR::Object::Reference are not created directly, but exist as a
concequence of class metadata creation.

=head1 PROPERTIES

=over 4

=item tha_id => Text

The ID property of UR::Object::Reference.  Its value is a composite of the
class name and the property name that triggered this Reference's creation.

=item class_name => Text

The name of the referencing class 

=item r_class_name => Text

The name of the referenced class

=item delegation_name => Text

The delegated property name that triggered the creation of this Reference.

=item constraint_name => Text

If the delegated property was created as a result of a foreign key in a 
database, this contains the name of that constraint.

=item class_meta => UR::Object::Type

The class metaobject named by class_name

=item r_class_meta => UR::Object::Type

The class metaobject named by r_class_name

=item reference_property_metas => UR::Object::Reference::Property

The list of reference property objects belonging to this Reference

=back

=head1 SEE ALSO

UR::Object::Reference::Property, UR::Object::Type, UR::Object::Type::Initializer

=cut
