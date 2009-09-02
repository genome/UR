package UR::Object::Property::Unique;

use strict;
use warnings;

=cut

UR::Object::Type->define(
    class_name => 'UR::Object::Property::Unique',
    english_name => 'entity type unique attribute',
    id_properties => [qw/type_name unique_group attribute_name/],
    properties => [
        attribute_name                   => { type => 'VARCHAR2', len => 64 },
        type_name                        => { type => 'VARCHAR2', len => 64 },
        unique_group                     => { type => 'VARCHAR2', len => 64 },
        class_name                       => { type => 'VARCHAR2', len => 64 },
        property_name                    => { type => 'VARCHAR2', len => 64 },
    ],
);

=cut

our $VERSION = '2.0';

sub create_object {
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
    return $class->SUPER::create_object(%params);
}



1;

