
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



use Storable qw(store_fd fd_retrieve);
BEGIN {
    my $ur_dir = substr($INC{'UR.pm'}, 0, length($INC{'UR.pm'})-5);
    #print "STDERR ur_dir is $ur_dir\n";
    my $dump;
    foreach my $dir ( '.', $ur_dir ) {
        if (-f "$dir/ur_core.stor" and -s _) {
            #print STDERR "Loading rules dump from $dir/ur_core.stor\n";
            open($dump, "$dir/ur_core.stor");
            last;
        } elsif (-f "$dir/ur_core.stor.gz" and -s _) {
            #print STDERR "Loading gzipped rules dump from $dir/ur_core.stor.gz\n";
            open($dump, "gzip -dc $dir/ur_core.stor.gz |");
            last;
        }
    }
    if ($dump) {
        $UR::DID_LOAD_FROM_DUMP = 1;

        local $/;
        my $data = fd_retrieve($dump);
        ($UR::Object::rule_templates, $UR::Object::rules) = @$data;
    }
}


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

END {
    if ($ENV{UR_USED_LIBS}) {
        print STDERR "Used libraries:\n";
        for my $lib (@INC) {
            print STDERR "$lib\n";
        }
    }
    if ($ENV{UR_USED_MODS}) {
        print STDERR "Used modules:\n";
        for my $mod (sort keys %INC) {
            print STDERR "$mod\n";
        }
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
        data_source_id                      => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        #data_source_meta                 => { type => 'UR::DataSource', id_by => 'data_source_id', is_optional => 1, source => 'data dictionary' },
        namespace                        => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },

        is_abstract                      => { type => 'Boolean', default_value => 0 },
        is_final                         => { type => 'Boolean', default_value => 0 },
        is_singleton                     => { type => 'Boolean', default_value => 0 },
        is_transactional                 => { type => 'Boolean', default_value => 1 },

        generated                        => { type => 'Boolean', is_transient => 1, default_value => 0 },
        meta_class_name                  => { type => 'Text' },

        short_name                       => { type => 'Text', len => 16, is_optional => 1, source => 'data dictionary' },
        source                           => { type => 'Text', len => 64 , default_value => 'data dictionary', is_optional => 1 }, # This is obsolete and should be removed later
        composite_id_separator           => { type => 'Text', len => 2 , default_value => "\t", is_optional => 1},        
        
        # These are part of refactoring away ::TableRow
        table_name                       => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },        
        query_hint                       => { type => 'Text', len => 1024 , is_optional => 1},        
        id_sequence_generator_name       => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary', doc => 'override the default choice for sequence generator name' },

        # Different ways of handling subclassing at object load time
        subclassify_by                      => { type => 'Text', len => 256, is_optional => 1},
        sub_classification_meta_class_name  => { type => 'Text', len => 1024 , is_optional => 1},
        sub_classification_method_name      => { type => 'Text', len => 256, is_optional => 1},
        first_sub_classification_method_name => { type => 'Text', len => 256, is_optional => 1 },
        subclass_description_preprocessor   => { is => 'MethodName', len => 255, is_optional => 1 },

    ### Relationships with the other meta-classes ###

        # UR::Namespaces are singletons referenced through their name
        namespace_meta                  => { type => 'UR::Namespace', id_by => 'namespace' },
        is                              => { type => 'ARRAY', is_mutable => 0, doc => 'List of the parent class names' },  
        

        # linking to the direct parents, and the complete ancestry
        parent_class_metas              => { type => 'UR::Object::Type', id_by => 'is',
                                             doc => 'The list of UR::Object::Type objects for the classes that are direct parents of this class' },#, is_many => 1 },
        parent_class_names              => { via => 'parent_class_metas', to => 'class_name', is_many => 1 },
        parent_meta_class_names         => { via => 'parent_class_metas', to => 'meta_class_name', is_many => 1 },
        ancestry_meta_class_names       => { via => 'ancestry_class_metas', to => 'meta_class_name', is_many => 1 },
        ancestry_class_metas            => { type => 'UR::Object::Type', id_by => 'is',  where => [-recurse => [class_name => 'is']],
                                             doc => 'Climb the ancestry tree and return the class objects for all of them' },
        ancestry_class_names            => { via => 'ancestry_class_metas', to => 'class_name', is_many => 1 },
        # This one isn't useful on its own, but is used to build the all_* accessors below
        all_class_metas                 => { type => 'UR::Object::Type', calculate => 'return ($self, $self->ancestry_class_metas)' },

        # Properties defined on this class, parent classes, etc.
        # There's also a property_meta_by_name() method defined in the class
        direct_property_metas            => { type => 'UR::Object::Property', reverse_id_by => 'class_meta', is_many => 1 },
        direct_property_names            => { via => 'direct_property_metas', to => 'property_name', is_many => 1 },
        #direct_id_property_metas         => { type => 'UR::Object::Property', reverse_id_by => 'class_meta', where => [ is_id => 1 ], is_many => 1 },
        #direct_id_property_names         => { via => 'direct_property_metas', to => 'property_name', is_many => 1, where => [ is_id => 1 ] },
        direct_id_property_metas         => { via => 'direct_id_token_metas', to => 'property_meta', is_many => 1 },
        direct_id_property_names         => { via => 'direct_id_token_metas', to => 'property_name', is_many => 1 },

        ancestry_property_metas          => { via => 'ancestry_class_metas', to => 'direct_property_metas', is_many => 1 },
        ancestry_property_names          => { via => 'ancestry_class_metas', to => 'direct_property_names', is_many => 1 },
        ancestry_id_property_metas       => { via => 'ancestry_class_metas', to => 'direct_id_property_metas', is_many => 1 },
        ancestry_id_property_names       => { via => 'ancestry_id_property_metas', to => 'property_name', is_many => 1 },

        all_property_metas               => { via => 'all_class_metas', to => 'direct_property_metas', is_many => 1 },
        all_property_names               => { via => 'all_property_metas', to => 'property_name', is_many => 1 },
        #all_id_property_metas            => { via => 'ancestry_property_metas', to => 'all_property_metas', where => [is_id => 1] },
        all_id_property_metas            => { via => 'all_id_token_metas', to => 'property_meta', is_many => 1 },
        all_id_property_names            => { via => 'all_id_token_metas', to => 'property_name', is_many => 1 },

        # these should go away when the is_id meta-property is working, since they don't seem that useful
        direct_id_token_metas            => { type => 'UR::Object::Property::ID', reverse_id_by => 'class_meta', is_many => 1 },
        direct_id_token_names            => { via => 'direct_id_token_metas', to => 'property_name', is_many => 1 },
        ancestry_id_token_metas          => { via => 'ancestry_class_metas', to => 'direct_id_token_metas', is_many => 1 },
        ancestry_id_token_names          => { via => 'ancestry_id_token_metas', to => 'property_name', is_many => 1 },
        all_id_token_metas               => { via => 'all_class_metas', to => 'direct_id_token_metas', is_many => 1 },

        # Unique contstraint trackers
        direct_unique_metas              => { type => 'UR::Object::Property::Unique', reverse_id_by => 'class_meta', is_many => 1 },
        direct_unique_property_metas     => { via => 'direct_unique_metas', to => 'property_meta', is_many => 1 },
        direct_unique_property_names     => { via => 'direct_unique_metas', to => 'property_name', is_many => 1 },
        ancestry_unique_property_metas   => { via => 'ancestry_class_metas', to => 'direct_unique_property_metas', is_many => 1 },
        ancestry_unique_property_names   => { via => 'ancestry_class_metas', to => 'direct_unique_property_names', is_many => 1 },
        all_unique_property_metas        => { via => 'all_class_metas', to => 'direct_unique_property_metas', is_many => 1 },
        all_unique_property_names        => { via => 'all_class_metas', to => 'direct_unique_property_names', is_many => 1 },

        # Datasource related stuff
        direct_column_names              => { via => 'direct_property_metas', to => 'column_name', is_many => 1, where => [column_name => { operator => 'true' }] },
        direct_id_column_names           => { via => 'get_direct_id_property_metas', to => 'column_name', is_many => 1, where => [column_name => { operator => 'true'}] },
        ancestry_column_names            => { via => 'ancestry_class_metas', to => 'direct_column_names', is_many => 1 },
        ancestry_id_column_names         => { via => 'ancestry_class_metas', to => 'direct_id_column_names', is_many => 1 },
        # Are these *columnless* properties actually necessary?  The user could just use direct_property_metas(column_name => undef)
        direct_columnless_property_metas => { is => 'UR::Object::Property', reverse_id_by => 'class_meta', where => [column_name => undef], is_many => 1 },
        direct_columnless_property_names => { via => 'direct_columnless_property_metas', to => 'property_name', is_many => 1 },
        ancestry_columnless_property_metas => { via => 'ancestry_class_metas', to => 'direct_columnless_property_metas', is_many => 1 },
        ancestry_columnless_property_names => { via => 'ancestry_columnless_property_metas', to => 'property_name', is_many => 1 },
        ancestry_table_names             => { via => 'ancestry_class_metas', to => 'table_name', is_many => 1 },
        all_table_names                  => { via => 'all_class_metas', to => 'table_name', is_many => 1 },
        all_column_names                 => { via => 'all_class_metas', to => 'direct_column_names', is_many => 1 },
        all_id_column_names              => { via => 'all_class_metas', to => 'direct_id_column_names', is_many => 1 },
        all_columnless_property_metas    => { via => 'all_class_metas', to => 'direct_columnless_property_metas', is_many => 1 },
        all_columnless_property_names    => { via => 'all_class_metas', to => 'direct_columnless_property_names', is_many => 1 },

        # Reference objects
        reference_metas                  => { type => 'UR::Object::Reference', reverse_id_by => 'class_meta', is_many => 1 },
        reference_property_metas         => { type => 'UR::Object::Reference::Property', via => 'reference_metas', to => 'reference_property_metas', is_many => 1 },
        all_reference_metas              => { via => 'all_class_metas', to => 'reference_metas', is_many => 1 },
        
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
        valid_values                    => { is => 'ARRAY', is_optional => 1, },
        doc                             => { type => 'Text', len => 1000, is_optional => 1 },
        is_id                           => { type => 'Boolean', default_value => 0, doc => 'denotes this is an ID property of the class' },
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
        reverse_id_by                   => { type => 'ARRAY', is_optional => 1 },
        implied_by                      => { type => 'Text' , is_optional => 1},
        via                             => { type => 'Text' , is_optional => 1 },
        to                              => { type => 'Text' , is_optional => 1},
        where                           => { type => 'ARRAY', is_optional => 1},
        calculate                       => { type => 'Text' , is_optional => 1},
        calculate_from                  => { type => 'ARRAY' , is_optional => 1},
        calculate_perl                  => { type => 'Perl' , is_optional => 1},
        calculate_sql                   => { type => 'SQL'  , is_optional => 1},
        calculate_js                    => { type => 'JavaScript' , is_optional => 1},
        constraint_name                 => { type => 'Text' , is_optional => 1},
        is_legacy_eav                   => { type => 'Boolean' , is_optional => 1},
        is_dimension                    => { type => 'Boolean', is_optional => 1},
        is_specified_in_module_header   => { type => 'Boolean', default_value => 0 },
        position_in_module_header       => { type => 'Integer', is_optional => 1, doc => "Line in the class definition source's section this property appears" },
        #rank                            => { type => 'Integer', is_optional => 1, doc => 'Order in which the properties are discovered while parsing the class definition' },
        singular_name                   => { type => 'Text' },
        plural_name                     => { type => 'Text' },

        class_meta                      => { type => 'UR::Object::Type', id_by => 'class_name' },
        unique_meta                     => { type => 'UR::Object::Property::Unique', reverse_id_by => 'property_meta', is_many => 1 },
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
        rank                            => { type => 'NUMBER', len => 2, source => 'data dictionary' },
        tha_id                          => { type => 'Text', len => 128, source => 'data dictionary' },
        attribute_name                  => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        r_attribute_name                => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        property_name                   => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
        r_property_name                 => { type => 'Text', len => 64, is_optional => 1, source => 'data dictionary' },
         
        reference_meta                  => { type => 'UR::Object::Reference', id_by => 'tha_id' },

        class_meta                      => { type => 'UR::Object::Type', via => 'reference_meta', to => 'class_meta' },
        class_name                      => { via => 'class_meta', to => 'class_name' },
	property_meta                   => { is => 'UR::Object::Property', id_by => [ 'class_name', 'property_name' ] },

        r_class_meta                    => { type => 'UR::Object::Type', via => 'reference_meta', to => 'r_class_meta' },
        r_class_name                    => { via => 'r_class_meta', to => 'class_name' },
        r_property_meta                 => { is => 'UR::Object::Property', id_by => [ 'r_class_name', 'r_property_name'] },
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

        reference_property_metas        => { type => 'UR::Object::Reference::Property', reverse_id_by => 'reference_meta', is_many => 1 },
        class_meta                      => { type => 'UR::Object::Type', id_by => 'class_name' },
        r_class_meta                    => { type => 'UR::Object::Type', id_by => 'r_class_name' },
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

        class_meta                       => { type => 'UR::Object::Type', id_by => 'class_name' },
        property_metas                   => { type => 'UR::Object::Property', id_by => ['class_name', 'property_name'] },
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

        class_meta                       => { type => 'UR::Object::Type', id_by => 'class_name' },
        property_meta                    => { type => 'UR::Object::Property', id_by => ['class_name', 'property_name'] },
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


sub main::ur_core {
    print STDERR "Dumping rules and templates to ./ur_core.stor...\n";
    my $dump;
    unless(open($dump, ">ur_core.stor")) {
        print STDERR "Can't open ur_core.stor for writing: $!";
        exit;
    }
    store_fd([
               $UR::Object::rule_templates,
               $UR::Object::rules,
              ],
             $dump);
    close $dump;
    exit();
}


1;
__END__

=head1 NAME

UR - the base module for the UR framework

=head1 VERSION

This document describes UR version 0.01

=head1 SYNOPSIS

First create a Namespace class for your application, CdExample.pm

    package CdExample;
    use UR;
    
    class CdExample {
        is => 'UR::Namespace'
    };
    
    1;

Next, define a data source representing your database, CdExample/DataSource/DB.pm

    package CdExample::DataSource::DB;
    use CdExample;
    
    class CdExample::DataSource::DB {
        is => ['UR::DataSource::Mysql', 'UR::Singleton'],
    };
    
    sub server { 'mysql.example.com' }
    sub login { 'mysqluser' }
    sub auth { 'mysqlpasswd' }
    1;

Create a class to represent artists, who have many CDs, in CdExample/Artist.pm

    package CdExample::Artist;
    use CdExample;

    class CdExample::Artist {
        id_by => 'artist_id',
        has => [ 
            name => { is => 'String' },
            cds  => { is => 'CdExample::Cd', is_many => 1, reverse_id_by => 'artist' }
        ],
        data_source => 'CdExample::DataSource::DB1',
        table_name => 'ARTISTS',
    };
    1;

Create a class to represent CDs, in CdExample/Cd.pm

    package CdExample::Cd;
    use CdExample;
            
    class CdExample::Cd {
        id_by => 'cd_id',
        has => [
            artist => { is => 'CdExample::Artist', id_by => 'artist_id' },
            title  => { is => 'String' },
            year   => { is => 'Integer' },
            artist_name => { via => 'artist', to => 'name' },
        ],
        data_source => 'CdExample::DataSource::DB',
        table_name => 'CDS',
    };
    1;

You can then use these classes in your application code

    use CdExample;  # Enables auto-loading for modules in this Namespace
    
    # get back all Artist objects
    my @all_artists = CdExample::Artist->get();
    # Iterate through Artist objects
    my $artist_iter = CdExample::Artist->create_iterator();
    # Get the first object off of the iterator
    my $first_artist = $artist_iter->next();

    # Get all the CDs published in 1997
    my @cds_1997 = CdExample::Cd->get(year => 1997);
    
    # Get a list of Artist objects where the name starts with 'John'
    my @some_artists = CdExample::Artist->get(name => { operator => 'like',
                                                        value => 'John%' });
    # Alternate syntax for non-equality operators
    my @same_some_artists = CdExample::Artist->get('name like' => 'John%');
    
    # This will use a JOIN with the ARTISTS table internally to filter
    # the data in the database.  @some_cds will contain CdExample::Cd objects.
    # As a side effect, related Artist objects will be loaded into the cache
    my @some_cds = CdExample::Cd->get(year => '2001', 
                                      artist_name => { operator => 'like',
                                                       value => 'Bob%' });
    my @artists_for_some_cds = map { $_->artist } @some_cds;
    
    # This will use a join to prefetch Artist objects related to the
    # Cds that match the filter
    my @other_cds = CdExample::Cd->get(title => { operator => 'like',
                                                  value => '%White%' },
                                       -hints => [ 'artist' ]);
    my $other_artist_0 = $other_cds[0]->artist;  # already loaded so no query
    
    # create() instantiates a new object in the cache, but does not save 
    # it in the database.  It will autogenerate its own cd_id
    my $new_cd = CdExample::Cd->create(title => 'Cool Album',
                                       year  => 2009 );
    # Assign it to an artist; fills in the artist_id field of $new_cd
    $first_artist->add_cd($new_cd);
    
    # Save all changes back to the database
    UR::Context->commit;
  
=head1 DESCRIPTION

UR is a class framework and object/relational mapper for Perl.  It starts
with the familiar Perl meme of the blessed hash reference as the basis for
object instances, and extends its capabilities with ORM (object-relational
mapping) capabilities, object cache, in-memory transactions, more formal
class definitions, metadata, documentation system, iterators, command line
tools, etc. 

UR can handle multiple column primary and foreign keys, SQL joins involving
class inheritance and relationships, and does its best to avoid querying
the database unless the requested data has not been loaded before.  It has
support for SQLite, Oracle, Mysql and Postgres databases, and the ability
to use a text file as a table.

=head1 DOCUMENTATION

L<UR::Manual> lists the other documentation pages in the UR distribution

=head1 Environment Variables

UR uses several environment variables to change its behavior.

=over 4

=item UR_CONTEXT_BASE <string>

The name of the base Context to instantiate when the program initializes.  It
defaults to whatever Root context exists.

=item UR_CONTEXT_ROOT <string>

The name of the Root context to instantiate when the program initializes.
The default is UR::Context::DefaultRoot.  Other Root Contexts can be used,
for example, to connect to alternate databases when running in test mode.

=item UR_CONTEXT_CACHE_SIZE_HIGHWATER <integer>

Set the object count highwater mark for the object cache pruner.  See also
L<UR::Context/object_cache_size_highwater>

=item UR_CONTEXT_CACHE_SIZE_LOWWATER <integer>

Set the object count lowwater mark for the object cache pruner.  See also
L<UR::Context/object_cache_size_lowwater>

=item UR_DBI_MONITOR_SQL <bool>

If this is true, most interactions with data sources such as connecting,
disconnecting and querying will print messages to STDERR.  Same as
C<UR::DBI-E<gt>monitor_sql()>.

=item UR_DBI_MONITOR_EVERY_FETCH <bool>

Used in conjunction with UR_DBI_MONITOR_SQL, tells the data sources to also
print messages to STDERR for each row fetched from the underlying data
source. Same as C<UR::DBI-E<gt>monitor_every_fetch()>.

=item UR_DBI_DUMP_STACK_ON_CONNECT <bool>

Print a message to STDERR only when connecting to an underlying data source.
Same as C<UR::DBI-E<gt>dump_stack_on_connect()>

=item UR_DBI_EXPLAIN_SQL_MATCH <string>

If the query to a data source matches the given string (interpreted as a
regex), then it will attempt to do an "explain plan" and print the results
before executing the query. Same as C<UR::DBI-E<gt>explain_sql_match()>

=item UR_DBI_EXPLAIN_SQL_SLOW <float>

If the time between a prepare and the first fetch of a query is longer than
the given number of seconds, then it will do an "explain plan" and print the
results.  Same as C<UR::DBI-E<gt>explain_sql_slow()>

=item UR_DBI_EXPLAIN_SQL_CALLSTACK <bool>

Used in conjunction with UR_DBI_EXPLAIN_SQL_MATCH and UR_DBI_EXPLAIN_SQL_SLOW,
prints a stack trace with Carp::longmess.  Same as C<UR::DBI-E<gt>explain_sql_callstack()>

=item UR_DBI_MONITOR_DML <bool>

Like UR_DBI_MONITOR_SQL, but only prints information during data-altering
statements, like INSERT, UPDATE or DELETE.  Same as C<UR::DBI-E<gt>monitor_dml()>

=item UR_DBI_NO_COMMIT <bool>

If true, data source commits will be ignored.  Note that saving still occurs.
If you are working with a RDBMS database, this means During
UR::Context->commit(), the insert, update and delete SQL statements will be
issued, but the changes will not be committed.  Useful for testing.  Same
as C<UR::DBI-E<gt>no_commit()>

=item UR_USE_DUMMY_AUTOGENERATED_IDS <bool>

If true, objects created without ID params will use a special algorithm to
generate IDs.  Objects with these special IDs will never be saved to a
data source.  Useful during testing.  Same as C<UR::DataSource-E<gt>use_dummy_autogenerated_ids>

=back

=head1 DEPENDENCIES

Class::Autouse

Cwd

Data::Dumper

Date::Calc

Date::Parse

DBI

File::Basename

FindBin

FreezeThaw

Path::Class

Scalar::Util

Sub::Installer

Sub::Name

Sys::Hostname

Text::Diff

Time::HiRes

XML::Simple

=head1 AUTHORS

 Scott Smith  ssmith@genome.wustl.edu
 Anthony Brummett abrummet@genome.wustl.edu
 Todd Hepler thepler@genome.wustl.edu

=head1 LICENCE AND COPYRIGHT

Copyright (C) 2009, Washington University in St. Louis

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

