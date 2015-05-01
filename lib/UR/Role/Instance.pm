package UR::Role::Instance;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => 'UR::Role::Instance',
    doc => 'Instance of a role composed into a class',
    id_by => ['role_name','class_name'],
    has => [
        role_name => { is => 'Text', doc => 'ID of the role prototype' },
        role_prototype => { is => 'UR::Role::Prototype', id_by => 'role_name' },
        class_name => { is => 'Test', doc => 'Class this role instance is composed into' },
        class_meta => { is => 'UR::Object::Type', id_by => 'class_name' },
        role_params => { is => 'HASH', doc => 'Parameters used when this role was composed', is_optional => 1 },
    ],
);

1;
