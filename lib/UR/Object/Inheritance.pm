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

1;
