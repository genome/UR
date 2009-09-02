
package UR::Object::Reference;

use strict;
use warnings;

=pod

UR::Object::Type->define(
    class_name => 'UR::Object::Reference',
    english_name => 'type has a',
    id_properties => ['tha_id'],
    properties => [
        tha_id                           => { type => 'NUMBER', len => 10 },
        accessor_name_for_id             => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        accessor_name_for_object         => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        class_name                       => { type => 'VARCHAR2', len => 64 },
        constraint_name                  => { type => 'VARCHAR2', len => 32, is_optional => 1 },
        delegation_name                  => { type => 'VARCHAR2', len => 64 },
        description                      => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        r_class_name                     => { type => 'VARCHAR2', len => 64 },
        r_delegation_name                => { type => 'VARCHAR2', len => 64 },
        r_type_name                      => { type => 'VARCHAR2', len => 64 },
        source                           => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        type_name                        => { type => 'VARCHAR2', len => 64 },
    ],
);

=cut

no warnings;

sub create_object {
    my $class = shift;
    my %params = @_;
    unless ($params{class_name} and $params{type_name}) {
        my $class_obj;
        if ($params{type_name}) {
            $class_obj = UR::Object::Type->is_loaded(type_name => $params{type_name});
            $params{class_name} = $class_obj->class_name;
        }
        elsif ($params{class_name}) {
            $class_obj = UR::Object::Type->is_loaded(class_name => $params{class_name});
            $params{type_name} = $class_obj->type_name;
        }
    }
    unless ($params{r_class_name} and $params{r_type_name}) {
        my $r_class_obj;
        if ($params{r_type_name}) {
            $r_class_obj = UR::Object::Type->is_loaded(type_name => $params{r_type_name});
            $params{r_class_name} = $r_class_obj->class_name;
        }
        elsif ($params{r_class_name}) {
            $r_class_obj = UR::Object::Type->is_loaded(class_name => $params{r_class_name});
            $params{r_type_name} = $r_class_obj->type_name;
        }
    }
    return $class->SUPER::create_object(%params);
}

sub generate
{
    my $self = shift;
    my $id = $self->id;
    print "generating $id\n";
    return 1;
}

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

sub property_link_names
{
    map { $_->property_name } shift->get_property_links(@_);
}

sub r_property_link_names
{
    map { $_->r_property_name } shift->get_property_links(@_);
}


1;
#$Header#
