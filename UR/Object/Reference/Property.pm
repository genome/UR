package UR::Object::Reference::Property;

use strict;
use warnings;

=cut

UR::Object::Type->define(
    class_name => 'UR::Object::Reference::Property',
    english_name => 'type attribute has a',
    id_properties => [qw/tha_id rank/],
    properties => [
        rank                             => { type => 'NUMBER', len => 2 },
        tha_id                           => { type => 'NUMBER', len => 10 },
        attribute_name                   => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        property_name                    => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        r_attribute_name                 => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        r_property_name                  => { type => 'VARCHAR2', len => 64, is_optional => 1 },
    ],
);

=cut

sub reference_id {
    # forward-compatible alias for the old "type has a" now "reference"
    shift->tha_id
}

sub create_object
{
    my $class = shift;
    my %params = @_;
    if ($params{attribute_name} and not $params{property_name}) {
        my $property_name = $params{attribute_name};
        $property_name =~ s/ /_/g;
        $params{property_name} = $property_name;
    }
    elsif ($params{property_name} and not $params{attribute_name}) {
        my $attribute_name = $params{property_name};
        $attribute_name =~ s/_/ /g;
        $params{attribute_name} = $attribute_name;
    }
    if ($params{r_attribute_name} and not $params{r_property_name}) {
        my $r_property_name = $params{r_attribute_name};
        $r_property_name =~ s/ /_/g;
        $params{r_property_name} = $r_property_name;
    }
    elsif ($params{r_property_name} and not $params{r_attribute_name}) {
        my $r_attribute_name = $params{r_property_name};
        $r_attribute_name =~ s/_/ /g;
        $params{r_attribute_name} = $r_attribute_name;
    }
    return $class->SUPER::create_object(%params);
}

sub _reference_class
{
    my $self = shift;
    if ($self->isa('UR::Object::Ghost')) {
        return 'UR::Object::Reference::Ghost';
    }
    else {
        return 'UR::Object::Reference';
    }
}

sub get_reference
{
    my $self = shift;
    return $self->_reference_class->get($self->tha_id);
}

sub class_name
{
    my $self = shift;
    my $r = $self->get_reference;
    return $r->class_name;
}


sub r_class_name
{
    shift->get_reference->r_class_name
}

sub get_with_special_parameters 
{
    my $class = shift;
    my $rule = shift;
    my %extra = @_;    
    if (my $class_name = delete $extra{class_name}) {
        unless (keys %extra) {
            # turn the class name into one or more ids for UR::Object::Reference.
            my @r = UR::Object::Reference->get(class_name => $class_name);
            return $class->get($rule->params_list, tha_id => \@r);
        }
    } elsif (my $r_class_name = delete $extra{r_class_name}) {
        unless (keys %extra) {
            # turn the class name into one or more ids for UR::Object::Reference.
            my @r = UR::Object::Reference->get(r_class_name => $r_class_name);
            return $class->get($rule->params_list, tha_id => \@r);
        }
    }
    return $class->SUPER::get_with_special_parameters($rule,@_);
}

1;
