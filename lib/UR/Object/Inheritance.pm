package UR::Object::Inheritance;

use warnings;
use strict;

=pod

use UR;

UR::Object::Type->define(
    class_name => 'UR::Object::Inheritance',
    english_name => 'type is a',
    id_properties => [qw/type_name parent_type_name/],
    properties => [
        parent_type_name                 => { type => 'VARCHAR2', len => 64 },
        type_name                        => { type => 'VARCHAR2', len => 64 },
        class_name                       => { type => 'VARCHAR2', len => 64 },
        inheritance_priority             => { type => 'NUMBER', len => 2 },
        parent_class_name                => { type => 'VARCHAR2', len => 64 },
    ],
);


=cut

sub create {
    my $class = shift;
    my %params = $class->preprocess_params(@_);

    my $class_object;
    if (!$params{type_name}) {
        if (my $class_name = $params{class_name}) {
            $class_object = UR::Object::Type->get(class_name => $class_name);
            unless ($class_object) {
                Carp::confess("Failed to find a class object for class $class_name!");
            }
            $params{type_name} = $class_object->type_name;
        }
        else {
            Carp::confess("Missing type_name!");
        }
    }
    if (!$params{parent_type_name}) {
        if (my $parent_class_name = $params{parent_class_name}) {
            my $parent_class_object = UR::Object::Type->get(class_name => $parent_class_name);
            unless ($parent_class_object) {
                Carp::confess("Failed to find a class object for class $parent_class_name!");
            }
            $params{parent_type_name} = $parent_class_object->type_name;
        }
        else {
            Carp::confess("Missing type_name!");
        }
    }
    $class->SUPER::create(%params);
}

1;
