
package UR;

use strict;
use warnings FATAL => 'all';

our $VERSION = '0.01';

# The UR module is itself a "UR::Namespace", besides being the root 
# module which bootstraps the system.  The class definition itself
# is made at the bottom of the file.

# Ensure we get detailed errors while starting up.
use Carp;
$SIG{__DIE__} = \&Carp::confess;

# Ensure that, if the application changes directory, we do not 
# change where we load modules while running.
use Cwd;
for my $dir (@INC) {
    next unless -d $dir;
    $dir = Cwd::abs_path($dir);
}

for my $e (keys %ENV) {
    next unless substr($e,0,3) eq 'UR_';
    eval "use UR::Env::$e";
    if ($@) {
        my $path = __FILE__;
        $path =~ s/.pm$//;
        my @files = glob($path . '/Env/*');
        my @vars = map { /UR\/Env\/(.*).pm/; $1 } @files; 
        print STDERR "Environment variable $e set to $ENV{$e} but there were errors using UR::Env::$e:\n"
            . "Available variables:\n\t" 
            . join("\n\t",@vars)
            . "\n";
        exit 1;
    }
}

#
# Because UR modules execute code when compiling to define their classes,
# and require each other for that code to execute, there are bootstrapping 
# problems.
#
# Everything which is part of the core framework "requires" UR 
# which, of course, executes AFTER it has compiled its SUBS,
# but BEFORE it defines its class.
#
# Everything which _uses_ the core of the framework "uses" its namespace,
# either the specific top-level namespace module, or "UR" itself for components/extensions.
#

require UR::Exit;
require UR::Util;
require UR::Time;

require UR::Report;         # this is used by UR::DBI
require UR::DBI;            # this needs a new name, and need only be used by UR::DataSource::RDBMS

require UR::ModuleBase;     # this should be switched to a role
require UR::ModuleConfig;   # used by ::Time, and also App's ::Lock ::Daemon

require UR::Object;         
require UR::Object::Type;

require UR::Object::Ghost;
require UR::Object::Inheritance;
require UR::Object::Type;
require UR::Object::Property;
require UR::Object::Property::ID;
require UR::Object::Property::Unique;
require UR::Object::Reference;
require UR::Object::Reference::Property;


require UR::BoolExpr::Util;
require UR::BoolExpr;                                  # has meta 

require UR::BoolExpr::Normalizer;                      # has meta
require UR::BoolExpr::Template;                        # has meta
require UR::BoolExpr::Template::PropertyComparison;    # has meta
require UR::BoolExpr::Template::Composite;             # has meta
require UR::BoolExpr::Template::And;                   # has meta    
require UR::BoolExpr::Template::Or;                    # has meta  

require UR::Object::Index;


#
# Define core metadata.
#
# This is done outside of the actual modules since the define() method
# uses all of the modules themselves to do its work.
#

UR::Object::Type->define(
    class_name => 'UR::Object',
    english_name => 'entity',
    is => [], # the default is to inherit from UR::Object, which is circular
    is_abstract => 1,
    composite_id_separator => "\t",
    id_by => [
        id  => { type => 'Scalar' }
    ]
);

UR::Object::Type->define(
    class_name => 'UR::Object::Inheritance',
    english_name => 'type is a',
    extends => ['UR::Object'],
    id_properties => [qw/type_name parent_type_name/],
    properties => [
        parent_type_name                 => { type => 'Text', len => 64, source => 'data dictionary' },
        type_name                        => { type => 'Text', len => 64, source => 'data dictionary' },
        parent_class_name                => { type => 'Text', len => 64, source => 'data dictionary' },
        class_name                       => { type => 'Text', len => 64, source => 'data dictionary' },
        inheritance_priority             => { type => 'NUMBER', len => 2 },
    ],
);

UR::Object::Type->define(
    class_name => "UR::Object::Index",
    english_name => "old index",
    id_by => ['indexed_class_name','indexed_property_string'],
    has => ['indexed_class_name','indexed_property_string'],
    is_transactional => 0,
);

UR::Object::Type->define(
    english_name => 'entity ghost',
    class_name => 'UR::Object::Ghost',
    is_abstract => 1,
);

UR::Object::Type->define(
    class_name => 'UR::Entity',
    english_name => 'table row',
    extends => ['UR::Object'],
    is_abstract => 1,
);

UR::Object::Type->define(
    class_name => 'UR::Entity::Ghost',
    english_name => 'table row ghost',
    extends => ['UR::Object::Ghost'],
    is_abstract => 1,
);

# MORE METADATA CLASSES

# For bootstrapping reasons, the properties with default values also need to be listed in
# %class_property_defaults defined in UR::Object::Type::Initializer.  If you make changes
# to default values, please keep these in sync.

UR::Object::Type->define(
    class_name => 'UR::Object::Type',
    english_name => 'entity type',
    id_by => ['class_name'],
    sub_classification_method_name => '_resolve_meta_class_name',
    has => [
        type_name                        => { type => 'Text', len => 64, source => 'data dictionary' },
        class_name                       => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        doc                              => { type => 'Text', len => 1024, is_optional => 1, source => 'data dictionary' },
        er_role                          => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary', default_value => 'entity' },
        schema_name                      => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        data_source                      => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        namespace                        => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },

        is_abstract                      => { type => 'Boolean', default_value => 0 },
        is_final                         => { type => 'Boolean', default_value => 0 },
        is_singleton                     => { type => 'Boolean', default_value => 0 },
        is_transactional                 => { type => 'Boolean', default_value => 1 },

        generated                        => { type => 'Boolean', is_transient => 1, default_value => 0 },

        short_name                       => { type => 'Text', len => 16, is_optional => 1, source => 'data dictionary' },
        source                           => { type => 'Text', len => 64 , default_value => 'data dictionary', is_optional => 1 }, # This is obsolete and should be removed later
        
        # These are part of refactoring away ::TableRow
        table_name                       => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },        
        query_hint                       => { type => 'Text', len => 1024 , is_optional => 1},        
        sub_classification_meta_class_name  => { type => 'Text', len => 1024 , is_optional => 1},
        sub_classification_property_name    => { type => 'Text', len => 256, is_optional => 1},
        sub_classification_method_name   => { type => 'Text', len => 256, is_optional => 1},

        first_sub_classification_method_name => { type => 'Text', len => 256, is_optional => 1 },
        
        composite_id_separator           => { type => 'Text', len => 2 , default_value => "\t", is_optional => 1},        
        subclass_description_preprocessor => { is => 'MethodName', len => 255, is_optional => 1 },
    ],    
    unique_constraints => [
        { properties => [qw/type_name/], sql => 'SUPER_FAKE_O2' },
        #{ properties => [qw/data_source table_name/], sql => 'SUPER_FAKE_05' },
    ],
);

UR::Object::Type->define(
    class_name => 'UR::Object::Property',
    english_name => 'entity type attribute',
    id_properties => [qw/class_name property_name/],
    properties => [
        property_type                   => { type => 'Text', len => 64 , is_optional => 1},
        class_name                      => { type => 'Text', len => 64 },        
        property_name                   => { type => 'Text', len => 64 },            
        type_name                       => { type => 'Text', len => 64 },        
        attribute_name                  => { type => 'Text', len => 64 },
        column_name                     => { type => 'Text', len => 64, is_optional => 1 },        
        data_length                     => { type => 'Text', len => 32, is_optional => 1 },
        data_type                       => { type => 'Text', len => 64, is_optional => 1 },
        default_value                   => { is_optional => 1 },
        doc                             => { type => 'Text', len => 1000, is_optional => 1 },
        is_optional                     => { type => 'Boolean' , default_value => 0},
        is_transient                    => { type => 'Boolean' , default_value => 0},
        is_constant                     => { type => 'Boolean' , default_value => 0},  # never changes
        is_mutable                      => { type => 'Boolean' , default_value => 1},  # can be changed explicitly via accessor (cannot be constant)
        is_volatile                     => { type => 'Boolean' , default_value => 0},  # changes w/o a signal: (cannot be constant or transactional)
        is_class_wide                   => { type => 'Boolean' , default_value => 0},
        is_delegated                    => { type => 'Boolean' , default_value => 0},
        is_calculated                   => { type => 'Boolean' , default_value => 0},
        is_transactional                => { type => 'Boolean' , default_value => 1},  # STM works on these, and the object can possibly save outside the app
        is_abstract                     => { type => 'Boolean' , default_value => 0},
        is_concrete                     => { type => 'Boolean' , default_value => 1},
        is_final                        => { type => 'Boolean' , default_value => 0},  
        is_many                         => { type => 'Boolean' , default_value => 0},
        is_deprecated                   => { type => 'Boolean', default_value => 0},
        is_numeric                      => { calculate_from => ['data_type'], },
        id_by                           => { type => 'ARRAY' , is_optional => 1},
        via                             => { type => 'Text' , is_optional => 1 },
        to                              => { type => 'Text' , is_optional => 1},
        where                           => { type => 'ParamList', is_optional => 1 },
        id_by                           => { type => 'ARRAY', is_optional => 1 },
        reverse_id_by                   => { type => 'ARRAY', is_optional => 1 },
        implied_by                      => { type => 'Text' , is_optional => 1},
        calculate                       => { type => 'Text' , is_optional => 1},
        calculate_from                  => { type => 'ARRAY' , is_optional => 1},
        calculate_perl                  => { type => 'Perl' , is_optional => 1},
        calculate_sql                   => { type => 'SQL'  , is_optional => 1},
        calculate_js                    => { type => 'JavaScript' , is_optional => 1},
        constraint_name                 => { type => 'Text' , is_optional => 1},
        is_legacy_eav                   => { type => 'Boolean' , is_optional => 1},
        is_dimension                    => { type => 'Boolean', is_optional => 1},
        is_specified_in_module_header   => { type => 'Boolean', default_value => 0 },
        position_in_module_header       => { type => 'Integer', is_optional => 1 },
        singular_name                   => { type => 'Text' },
        plural_name                     => { type => 'Text' },
    ],
    unique_constraints => [
        { properties => [qw/property_name type_name/], sql => 'SUPER_FAKE_O4' },
    ],
);


UR::Object::Type->define(
    class_name => 'UR::Object::Reference::Property',
    english_name => 'type attribute has a',
    id_properties => [qw/tha_id rank/],
    properties => [
        rank                             => { type => 'NUMBER', len => 2, source => 'data dictionary' },
        tha_id                           => { type => 'Text', len => 128, source => 'data dictionary' },
        attribute_name                   => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        r_attribute_name                 => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        property_name                    => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        r_property_name                  => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
    ],
);

UR::Object::Type->define(
    class_name => 'UR::Object::Reference',
    english_name => 'type has a',
    id_properties => ['tha_id'],
    properties => [
        tha_id                          => { type => 'Text', len => 128, source => 'data dictionary' },
        class_name                      => { type => 'Text', len => 64, is_optional => 0, source => 'data dictionary' },
        type_name                       => { type => 'Text', len => 64, is_optional => 0, source => 'data dictionary' },
        delegation_name                 => { type => 'Text', len => 64, is_optional => 0, source => 'data dictionary' },
        r_class_name                    => { type => 'Text', len => 64, is_optional => 0, source => 'data dictionary' },
        r_type_name                     => { type => 'Text', len => 64, is_optional => 0, source => 'data dictionary' },
        #r_delegation_name               => { type => 'Text', len => 64, is_optional => 0, source => 'data dictionary' },
        constraint_name                 => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        source                          => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        description                     => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        accessor_name_for_id            => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        accessor_name_for_object        => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
    ],
);

UR::Object::Type->define(
    class_name => 'UR::Object::Property::Unique',
    english_name => 'entity type unique attribute',
    id_properties => [qw/type_name unique_group attribute_name/],
    properties => [
        class_name                       => { type => 'Text', len => 64, source => 'data dictionary' },
        type_name                        => { type => 'Text', len => 64, source => 'data dictionary' },
        property_name                    => { type => 'Text', len => 64, source => 'data dictionary' },
        attribute_name                   => { type => 'Text', len => 64, source => 'data dictionary' },
        unique_group                     => { type => 'Text', len => 64, source => 'data dictionary' },
    ],
);


UR::Object::Type->define(
    class_name => 'UR::Object::Property::ID',
    english_name => 'entity type id',
    id_properties => [qw/type_name position/],
    properties => [
        position                         => { type => 'NUMBER', len => 2, source => 'data dictionary' },
        class_name                       => { type => 'Text', len => 64, source => 'data dictionary' },
        type_name                        => { type => 'Text', len => 64, source => 'data dictionary' },
        attribute_name                   => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        property_name                    => { type => 'Text', len => 64, source => 'data dictionary' },
    ],
);

UR::Object::Type->define(
    class_name => 'UR::Object::Property::Calculated::From',
    id_properties => [qw/class_name calculated_property_name source_property_name/],
);

require UR::Singleton;
require UR::Namespace;

UR::Object::Type->define(
    class_name => 'UR',
    extends => ['UR::Namespace'],
);

require UR::Context;
UR::Object::Type->initialize_bootstrap_classes;
require Command;

$UR::initialized = 1;

require UR::Change;
require UR::Command::Param;
require UR::Context::Root;
require UR::Context::Process;
require UR::Object::Tag;

do {
    UR::Context->_initialize_for_current_process();
};

require UR::Moose;          # a no-op unless UR_MOOSE is set to true currently
require UR::ModuleLoader;   # signs us up with Class::Autouse

1;
__END__

=head1 NAME

UR - the base module for the UR framework

=head1 VERSION

This document describes UR version 0.01

=head1 SYNOPSIS

use UR;

TODO
  
=head1 DESCRIPTION

TODO

=head1 INTERFACE 

TODO

=head1 DIAGNOSTICS

TODO

=head1 CONFIGURATION AND ENVIRONMENT

TODO

=head1 DEPENDENCIES

Date::Calc

Class::Autouse

Sub::Installer

Sub::Name

=head1 INCOMPATIBILITIES

TODO

=head1 BUGS AND LIMITATIONS

TODO

=head1 AUTHORS

<Scott Smith>  C<< <<ssmith@genome.wustl.edu>> >>
<Todd Hepler>  C<< <<thepler@genome.wustl.edu>> >>

=head1 LICENCE AND COPYRIGHT

Copyright (C) 2007, Washington University in St. Louis

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

