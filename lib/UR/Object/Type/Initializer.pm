
# This line forces correct deployment by gsc-scripts.
package UR::Object::Type::Initializer;

package UR::Object::Type;

use strict;
use warnings;

use Carp ();
use Sub::Name ();
use Sub::Install ();

our @CARP_NOT = qw( UR::ModuleLoader Class::Autouse );

# keys are class property names (like er_role, is_final, etc) and values are
# the default value to use if it's not specified in the class definition
#
# For most classes, this kind of thing is handled by the default_value attribute on
# a class' property.  For bootstrapping reasons, the default values for the
# properties of UR::Object::Type' class need to be listed here as well.  If
# any of these change, or new default valued items are added, be sure to also
# update the class definition for UR::Object::Type (which really lives in UR.pm 
# for the moment)
%UR::Object::Type::defaults = (
    er_role            => 'entity',
    is_final           => 0,
    is_singleton       => 0,
    is_transactional   => 1,
    is_mutable         => 1,
    is_many            => 0,
    is_abstract        => 0,
);

# All those same comments also apply to UR::Object::Property's properties
%UR::Object::Property::defaults = (
    is_optional      => 0,
    is_transient     => 0,
    is_constant      => 0,
    is_volatile      => 0,
    is_class_wide    => 0,
    is_delegated     => 0,
    is_calculated    => 0,
    is_mutable       => undef,
    is_transactional => 1,
    is_abstract      => 0,
    is_concrete      => 1,
    is_final         => 0,
    is_many          => 0,
    is_numeric       => 0,
    is_specified_in_module_header => 0,
    is_deprecated    => 0,
    position_in_module_header => -1,
);

@UR::Object::Type::meta_id_ref_shared_properties = (
    qw/
        is_optional
        is_transient
        is_constant
        is_volatile
        is_class_wide
        is_transactional
        is_abstract
        is_concrete
        is_final
        is_many
        is_deprecated
    /
);

%UR::Object::Type::converse = (
    required => 'optional',
    abstract => 'concrete',
    one => 'many',
);

# These classes are used to define an object class.
# As such, they get special handling to bootstrap the system.

our %meta_classes = map { $_ => 1 }
    qw/
        UR::Object
        UR::Object::Type
        UR::Object::Property
    /;

our $bootstrapping = 1;
our @partially_defined_classes;

# When copying the object hash to create its db_committed, these keys should be removed because
# they contain things like coderefs
our @keys_to_delete_from_db_committed = qw( id db_committed _id_property_sorter get_composite_id_resolver get_composite_id_decomposer );

# Stages of Class Initialization
#
# define() is called to indicate the class structure (create() may also be called by the db sync command to make new classes)
#
# the parameters to define()/create() are normalized by _normalize_class_description()
#
# a basic functional class meta object is created by _define_minimal_class_from_normalized_class_description()
#
#  accessors are created
#
# if we're still bootstrapping:
#
#  the class is stashed in an array so the post-boostrapping stages can be done in bulk
#
#  we exit define()
#  
# if we're done bootstrapping:
#
# _inform_all_parent_classes_of_newly_loaded_subclass() sets up an internal map of known subclasses of each base class
#
# _complete_class_meta_object_definitions() decomposes the definition into normalized objects
#

sub create {
    my $class = shift;
    my $desc = $class->_normalize_class_description(@_);
    
    my $class_name = $desc->{class_name} ||= (caller(0))[0];
    my $meta_class_name = $desc->{meta_class_name};
    
    no strict 'refs';
    unless (
        $meta_class_name eq __PACKAGE__ 
        or 
        # in newer Perl interpreters the ->isa() call can return true
        # even if @ISA has been emptied (OS X) ???
        (scalar(@{$meta_class_name . '::ISA'}) and $meta_class_name->isa(__PACKAGE__))
    ) {
        if (__PACKAGE__->get(class_name => $meta_class_name)) {
            warn "class $meta_class_name already exists when creating class meta for $class_name?!";
        }
        else {
            __PACKAGE__->create(
                __PACKAGE__->_construction_params_for_desc($desc)
            );
        }
    }

    my $self = $class->_make_minimal_class_from_normalized_class_description($desc);
    Carp::confess("Failed to define class $class_name!") unless $self;
        
    $self->_initialize_accessors_and_inheritance
        or Carp::confess("Failed to define class $class_name!");
    
    $self->_inform_all_parent_classes_of_newly_loaded_subclass()
        or Carp::confess(
            "Failed to link to parent classes to complete definition of class $class_name!"
            . $class->error_message
        );
        
    $self->generated(0);
    
    $self->__signal_change__("create");
    
    return $self;
}

sub _preprocess_subclass_description {
    # allow a class to modify the description of any subclass before it instantiates
    # this filtering allows a base class to specify policy, add meta properties, etc.
    my ($self,$prev_desc) = @_;

    my $current_desc = $prev_desc;

    if (my $preprocessor = $self->subclass_description_preprocessor) {
        # the preprocessor must me a method name in the class being adjusted
        no strict 'refs';
        unless ($self->class_name->can($preprocessor)) {
            die "Class " . $self->class_name 
                . " specifies a pre-processor for subclass descriptions "
                . $preprocessor . " which is not defined in the " 
                . $self->class_name . " package!";
        }
        $current_desc = $self->class_name->$preprocessor($current_desc);
    }

    # only call it on the direct parent classes, let recursion walk the tree
    my @parent_class_names = 
        grep { $_->can('__meta__') } 
        $self->parent_class_names();

    for my $parent_class_name (@parent_class_names) {
        my $parent_class = $parent_class_name->__meta__;
        $current_desc = $parent_class->_preprocess_subclass_description($current_desc);
    }

    return $current_desc;
}

sub _construction_params_for_desc {
    my $class = shift;
    my $desc = shift;

    my $class_name = $desc->{class_name};
    my $meta_class_name = $desc->{meta_class_name};
    my @extended_metadata;
    if ($desc->{type_has}) {
        @extended_metadata = ( has => [ @{ $desc->{type_has} } ] );
    }

    if (
        $meta_class_name eq __PACKAGE__ 
    ) {
        if (@extended_metadata) {
            die "Cannot extend class metadata of $class_name because it is a class involved in UR boostrapping.";
        }
        return();
    }
    else {
        if ($bootstrapping) {
            return (
                class_name => $meta_class_name,
                is => __PACKAGE__,
                @extended_metadata,
            );
        }
        else {
            my $parent_classes = $desc->{is};
            my @meta_parent_classes = map { $_ . '::Type' } @$parent_classes;
            for (@$parent_classes) {
                __PACKAGE__->use_module_with_namespace_constraints($_);
                eval {$_->class};
                if ($@) {
                    die "Error with parent class $_ when defining $class_name! $@";
                }
            }
            return (
                class_name => $meta_class_name,
                is => \@meta_parent_classes,
                @extended_metadata,
            );
        }
    }

}

sub __define__ {
    my $class = shift;
    my $desc = $class->_normalize_class_description(@_);
    
    my $class_name = $desc->{class_name} ||= (caller(0))[0];
    $desc->{class_name} = $class_name;

    my $self; 

    my %params = $class->_construction_params_for_desc($desc);
    my $meta_class_name;
    if (%params) {
        $self = __PACKAGE__->__define__(%params);
        return unless $self;
        $meta_class_name = $params{class_name};
    }
    else {
        $meta_class_name = __PACKAGE__;
    }
    
    $self = $UR::Context::all_objects_loaded->{$meta_class_name}{$class_name};
    if ($self) {
        $DB::single = 1;
        #Carp::cluck("Re-defining class $class_name?  Found $meta_class_name with id '$class_name'");
        return $self;
    }
    
    $self = $class->_make_minimal_class_from_normalized_class_description($desc);
    Carp::confess("Failed to define class $class_name!") unless $self;
    
    # we do this for define() but not create()
    my %db_committed = %$self;
    delete @db_committed{@keys_to_delete_from_db_committed};
    $self->{'db_committed'} = \%db_committed;

    $self->_initialize_accessors_and_inheritance 
        or Carp::confess("Error initializing accessors for $class_name!");

    if ($bootstrapping) {
        push @partially_defined_classes, $self;
    }
    else {
        unless ($self->_inform_all_parent_classes_of_newly_loaded_subclass()) {
            Carp::confess(
                "Failed to link to parent classes to complete definition of class $class_name!"
                . $class->error_message
            );            
        }
        unless ($self->_complete_class_meta_object_definitions()) {
            $DB::single = 1;
            $self->_complete_class_meta_object_definitions();
            Carp::confess(
                "Failed to complete definition of class $class_name!"
                . $class->error_message
            );
        }     
    }
    return $self; 
}


sub initialize_bootstrap_classes 
{
    # This is called once at the end of compiling the UR module set to handle 
    # classes which did incomplete initialization while bootstrapping.
    # Until bootstrapping occurs is done, 
    my $class = shift;
    
    for my $class_meta (@partially_defined_classes) {
        unless ($class_meta->_inform_all_parent_classes_of_newly_loaded_subclass) {
            my $class_name = $class_meta->{class_name};
            Carp::confess (
                "Failed to complete inheritance linkage definition of class $class_name!"
                . $class_meta->error_message
            );
        }                    
        
    }
    while (my $class_meta = shift @partially_defined_classes) {
        unless ($class_meta->_complete_class_meta_object_definitions()) {
            my $class_name = $class_meta->{class_name};
            Carp::confess(
                "Failed to complete definition of class $class_name!"
                . $class_meta->error_message
            );
        }
    }    
    $bootstrapping = 0;

    # It should be safe to set up callbacks now.
    UR::Object::Property->create_subscription(callback => \&UR::Object::Type::_property_change_callback);
}

sub _normalize_class_description {
    my $class = shift;
    my %old_class = @_;

    my $class_name = delete $old_class{class_name};    

    my %new_class = (
        class_name      => $class_name,        
        is_singleton    => $UR::Object::Type::defaults{'is_singleton'},
        is_final        => $UR::Object::Type::defaults{'is_final'},
        is_abstract     => $UR::Object::Type::defaults{'is_abstract'},
    );

    for my $mapping (
        [ class_name            => qw//],
        [ type_name             => qw/english_name/],
        [ is                    => qw/inheritance extends isa is_a/],        
        [ is_abstract           => qw/abstract/],
        [ is_final              => qw/final/],
        [ is_singleton          => qw//],
        [ is_transactional      => qw//],        
        [ id_by                 => qw/id_properties/],
        [ has                   => qw/properties/],        
        [ type_has              => qw//],
        [ attributes_have       => qw//],
        [ er_role               => qw/er_type/],        
        [ doc                   => qw/description/],        
        [ relationships         => qw//],
        [ constraints           => qw/unique_constraints/],
        [ namespace             => qw//],
        [ schema_name           => qw//],                
        [ data_source_id        => qw/data_source instance/],                
        [ table_name            => qw/sql dsmap/],
        [ query_hint            => qw/query_hint/],
        [ subclassify_by        => qw/sub_classification_property_name/],
        [ sub_classification_meta_class_name    => qw//],
        [ sub_classification_method_name        => qw//],
        [ first_sub_classification_method_name  => qw//],
        [ composite_id_separator                => qw//],
        [ generate              => qw//],
        [ generated             => qw//],
        [ subclass_description_preprocessor => qw//],        
        [ id_sequence_generator_name => qw//],
    ) {        
        my ($primary_field_name, @alternate_field_names) = @$mapping;                
        my @all_fields = ($primary_field_name, @alternate_field_names);
        my @values = grep { defined($_) } delete @old_class{@all_fields};
        if (@values > 1) {
            Carp::confess(
                "Multiple values in class definition for $class_name for field "
                . join("/", @all_fields)
            );
        }
        elsif (@values == 1) {
            $new_class{$primary_field_name} = $values[0];
        }
    }

    if (my $pp = $new_class{subclass_description_preprocessor}) {
        if (!ref($pp)) {
            unless ($pp =~ /::/) {
                # a method name, not fully qualified
                $new_class{subclass_description_preprocessor} = 
                    $new_class{class_name} 
                        . '::' 
                            . $new_class{subclass_description_preprocessor};
            } else {
                $new_class{subclass_description_preprocessor} = $pp;
            }
        }
        elsif (ref($pp) ne 'CODE') {
            die "unexpected " . ref($pp) . " reference for subclass_description_preprocessor for $class_name!";
        } 
    }

    unless ($new_class{er_role}) {
        $new_class{er_role} = $UR::Object::Type::defaults{'er_role'};
    }   
 
    my @crap = qw/source short_name/;
    delete @old_class{@crap};
    
    if ($class_name =~ /^(.*?)::/) {
        $new_class{namespace} = $1;
    }
    else {
        $new_class{namespace} = $new_class{class_name};
    }
    
    if (not exists $new_class{is_transactional}
        and not $meta_classes{$class_name}
    ) {
        $new_class{is_transactional} = $UR::Object::Type::defaults{'is_transactional'};
    }
   
    unless ($new_class{is}) {
        no warnings;
        no strict 'refs';
        if (my @isa = @{ $class_name . "::ISA" }) {
            $new_class{is} = \@isa;
        }
    }
    
    unless ($new_class{is}) {
        if ($new_class{table_name}) {
            $new_class{is} = ['UR::Entity']
        }
        else {
            $new_class{is} = ['UR::Object']
        }
    }

    $new_class{table_name} = uc($new_class{table_name}) if ($new_class{table_name} and $new_class{table_name} !~ /\s/);

    unless ($new_class{'doc'}) {
        $new_class{'doc'} = undef;
    }
  
    for my $field (qw/is id_by has relationships constraints/) {
        next unless exists $new_class{$field};
        my $reftype = ref($new_class{$field});
        if (! $reftype) {
            # It's a plain string, wrap it in an arrayref
            $new_class{$field} = [ $new_class{$field} ];
        } elsif ($reftype eq 'HASH') {
            # Later code expects it to be a listref - convert it
            my @params_as_list;
            foreach my $attr_name ( keys (%{$new_class{$field}}) ) {
                push @params_as_list, $attr_name;
                push @params_as_list, $new_class{$field}->{$attr_name};
            }
            $new_class{$field} = \@params_as_list;
        } elsif ($reftype ne 'ARRAY') {
            die "Class $class_name cannot initialize because its $field section is not a string, arrayref or hashref";
        }
    }
    
    # These may have been found and moved over.  Restore.
    $old_class{has}             = delete $new_class{has};
    $old_class{attributes_have} = delete $new_class{attributes_have};
    

    # Install structures to track fully formatted property data.
    my $instance_properties = $new_class{has} = {};
    my $meta_properties     = $new_class{attributes_have} = {};
    
    # The id might be a single value, or not specified at all.
    my $id_properties;
    if (not exists $new_class{id_by}) {
        if ($new_class{is}) {
            $id_properties = $new_class{id_by} = [];
        }
        else {
            $id_properties = $new_class{id_by} = [ id => { is_optional => 0 } ];
        }
    }
    elsif ( (not ref($new_class{id_by})) or (ref($new_class{id_by}) ne 'ARRAY') ) {
        $id_properties = $new_class{id_by} = [ $new_class{id_by} ];
    }
    else {
        $id_properties = $new_class{id_by};
    }
    
    # Transform the id properties into a list of raw ids, 
    # and move the property definitions into "id_implied" 
    # where present so they can be processed below.
    my $property_rank = 0;
    do {
        my @replacement;
        my $pos = 0;
        for (my $n = 0; $n < @$id_properties; $n++) {
            my $name = $id_properties->[$n];
            
            my $data = $id_properties->[$n+1];
            if (ref($data)) {
                $old_class{id_implied}->{$name} ||= $data;
                if (my $obj_ids = $data->{id_by}) {
                    push @replacement, (ref($obj_ids) ? @$obj_ids : ($obj_ids));
                }
                else {
                    push @replacement, $name;
                }
                $n++;
            }
            else {
                $old_class{id_implied}->{$name} ||= {};
                push @replacement, $name;
            }
            $old_class{id_implied}->{$name}->{'position_in_module_header'} = $pos++;
        }
        @$id_properties = @replacement;
    };
    
    if (@$id_properties > 1
        and grep {$_ eq 'id'} @$id_properties)
    {
        Carp::croak("Cannot initialize class $class_name: "
                    . "Cannot have an ID property named 'id' when the class has multiple ID properties ("
                    . join(', ', map { "'$_'" } @$id_properties)
                    . ")");
    }

    # Flatten and format the property list(s) in the class description.
    # NOTE: we normalize the details at the end of normalizing the class description.
    my @keys = grep { /has|attributes_have/ } keys %old_class;
    unshift @keys, qw(id_implied); # we want to hit this first to preserve position_ and is_specified_ keys
    my @properties_in_class_definition_order;
    foreach my $key ( @keys ) {
        # parse the key to see if we're looking at instance or meta attributes,
        # and take the extra words as additional attribute meta-data. 
        my @added_property_meta;
        my $properties;
        if ($key =~ /has/) {
            @added_property_meta =
                grep { $_ ne 'has' } split(/[_-]/,$key);
            $properties = $instance_properties;
        }
        elsif ($key =~ /attributes_have/) {
            @added_property_meta =
                grep { $_ ne 'attributes' and $_ ne 'have' } split(/[_-]/,$key);
            $properties = $meta_properties;
        }
        elsif ($key eq 'id_implied') {
            # these are additions to the regular "has" list from complex identity properties
            $properties = $instance_properties;
        }
        else {
            die "Odd key $key?";
        }
        @added_property_meta = map { 'is_' . $_ => 1 } @added_property_meta;

        # the property data can be a string, array, or hash as they come in       
        # convert string, hash and () into an array
        my $property_data = delete $old_class{$key};

        my @tmp;
        if (!ref($property_data)) {
            if (defined($property_data)) {
                @tmp  = split(/\s+/, $property_data);
            }
            else {
                @tmp = (); 
            }
        }
        elsif (ref($property_data) eq 'HASH') {
            @tmp = map {                    
                    ($_ => $property_data->{$_})
                } sort keys %$property_data;
        }
        elsif (ref($property_data) eq 'ARRAY') {
            @tmp = @$property_data;    
        }
        else {
            die "Unrecognized data $property_data appearing as property list!";
        }
        
        # process the array of property specs
        my $pos = 0;
        while (my $name = shift @tmp) {
            my $params;
            if (ref($tmp[0])) {
                $params = shift @tmp;
                unless (ref($params) eq 'HASH') {
                    my $seen_type = ref($params);
                    Carp::confess("class $class_name property $name has a $seen_type reference instead of a hashref describing its meta-attributes!");
                }
                %$params = (@added_property_meta, %$params) if @added_property_meta;
            }
            else {
                $params = { @added_property_meta };
            }       
                     
            unless (exists $params->{'position_in_module_header'}) {
                $params->{'position_in_module_header'} = $pos++;
            }
            unless (exists $params->{is_specified_in_module_header}) {
                $params->{is_specified_in_module_header} = $class_name . '::' . $key;
            }
            
            # Indirect properties can mention the same property name more than once.  To
            # avoid stomping over existing property data with this other property data,
            # merge the new info into the existing hash.  Otherwise, the new property name
            # gets an empty hash of info
            if ($properties->{$name}) {
                # this property already exists, but is also implied by some other property which added it to the end of the listed
                # extend the existing definition
                foreach my $key ( keys %$params ) {
                    next if ($key eq 'is_specified_in_module_header' || $key eq 'position_in_module_header');
                    $properties->{$name}->{$key} = $params->{$key};
                }
            } else {
                $properties->{$name} = $params;
            }
            push @properties_in_class_definition_order, $name;

            # a single calculate_from can be a simple string, convert to a listref
            if (my $calculate_from = $params->{'calculate_from'}) {
                $params->{'calculate_from'} = [ $calculate_from ] unless (ref($calculate_from) eq 'ARRAY');
            }
            
            if (my $id_by = $params->{id_by}) {
                $id_by = [ $id_by ] unless ref($id_by) eq 'ARRAY';
                my @id_by_names;
                while (@$id_by) {
                    my $id_name = shift @$id_by;
                    my $params2;
                    if (ref($id_by->[0])) {
                        $params2 = shift @$id_by;
                    }
                    else {
                        $params2 = {};
                    }
                    for my $p (@UR::Object::Type::meta_id_ref_shared_properties) {
                        if (exists $params->{$p}) {
                            $params2->{$p} = $params->{$p};
                        }
                    }                    
                    $params2->{implied_by} = $name;
                    $params2->{is_specified_in_module_header} = 0;                    
                    push @id_by_names, $id_name;
                    push @tmp, $id_name, $params2;
                }
                $params->{id_by} = \@id_by_names;
            }
        } # next property in group

        for my $pdata (values %$properties) {
            next unless $pdata->{id_by};
            for my $id_property (@{ $pdata->{id_by} }) {
                my $id_pdata = $properties->{$id_property};
                for my $p (@UR::Object::Type::meta_id_ref_shared_properties) {
                    if (exists $id_pdata->{$p}) {
                        $pdata->{$p} = $id_pdata->{$p};
                    }
                }                    
            }
        }
    } # next group of properties
   
    # NOT ENABLED YET
    if (0) {
    # done processing direct properties of this process
    # extend %$instance_properties with properties of the parent classes
    my @parent_class_names = @{ $new_class{is} };
    for my $parent_class_name (@parent_class_names) {
        my $parent_class_meta = $parent_class_name->__meta__;
        die "no meta for $parent_class_name while initializing $class_name?" unless $parent_class_meta;
        my $parent_normalized_properties = $parent_class_meta->{has};
        for my $parent_property_name (keys %$parent_normalized_properties) {
            my $parent_property_data = $parent_normalized_properties->{$parent_property_name};
            my $inherited_copy = $instance_properties->{$parent_property_name};
            unless ($inherited_copy) {
                $inherited_copy = UR::Util::deep_copy($parent_property_data);
            }
            $inherited_copy->{class_name} = $class_name;
            my $a = $inherited_copy->{overrides_class_names} ||= [];
            push @$a, $parent_property_data->{class_name};
        }
    }
    }

    $new_class{'__properties_in_class_definition_order'} = \@properties_in_class_definition_order;
    
    unless ($new_class{type_name}) {
        $new_class{type_name} = $new_class{class_name};
    }
    
    if (($new_class{data_source_id} and not ref($new_class{data_source_id})) and not $new_class{schema_name}) {
        my $s = $new_class{data_source_id};
        $s =~ s/^.*::DataSource:://;
        $new_class{schema_name} = $s;
    }
     
    if (%old_class) {
        # this should have all been deleted above
        # we actually process it later, since these may be related to parent classes extending
        # the class definition
        $new_class{extra} = \%old_class;
    };

    # cascade extra meta attributes from the parent downward
    unless ($bootstrapping) {
        my @additional_property_meta_attributes;
        for my $parent_class_name (@{ $new_class{is} }) {
            no warnings;
            unless ($parent_class_name->can("__meta__")) {
                __PACKAGE__->use_module_with_namespace_constraints($parent_class_name);
                die "Class $class_name cannot initialize because of errors using parent class $parent_class_name: $@" if $@; 
            }
            unless ($parent_class_name->can("__meta__")) {
                die "Class $class_name cannot initialize because of errors using parent class $parent_class_name.  Failed to find static method '__meta__' on $parent_class_name!"; 
            }
            my $parent_class = $parent_class_name->__meta__;
            unless ($parent_class) {
                warn "no class metadata bject for $parent_class_name!";
                next;
            }
            if (my $parent_meta_properties = $parent_class->{attributes_have}) {
                push @additional_property_meta_attributes, %$parent_meta_properties;
            }
        }
        #print "inheritance for $class_name has @additional_property_meta_attributes\n";
        %$meta_properties = (%$meta_properties, @additional_property_meta_attributes);

        # Inheriting from an abstract class that subclasses with a subclassify_by means that
        # this class' property named by that subclassify_by is actually a constant equal to this
        # class' class name
        PARENT_CLASS:
        foreach my $parent_class_name ( @{ $new_class{'is'} }) {
            my $parent_class_meta = $parent_class_name->__meta__();
            foreach my $ancestor_class_meta ( $parent_class_meta->all_class_metas ) {
                if (my $subclassify_by = $ancestor_class_meta->subclassify_by) {
                    $instance_properties->{$subclassify_by} ||= { property_name => $subclassify_by,
                                                                  default_value => $class_name,
                                                                  is_constant => 1,
                                                                  is_class_wide => 1,
                                                                  is_specified_in_module_header => 0,
                                                                  column_name => '',
                                                                  implied_by => $parent_class_meta->class_name . '::subclassify_by',
                                                                };
                    last PARENT_CLASS;
                }
            }
        }
    }

    # normalize the data behind the property descriptions    
    my @property_names = keys %$instance_properties;
    for my $property_name (@property_names) {
        my %old_property = %{ $instance_properties->{$property_name} };        
        my %new_property = $class->_normalize_property_description($property_name, \%old_property, \%new_class);
        $instance_properties->{$property_name} = \%new_property;
    }

    # Find 'via' properties where the to is '-filter' and rewrite them to 
    # copy some attributes from the source property 
    # This feels like a hack, but it makes other parts of the system easier by
    # not having to deal with -filter
    foreach my $property_name ( @property_names ) {
        my $property_data = $instance_properties->{$property_name};
        if ($property_data->{'to'} && $property_data->{'to'} eq '-filter') {
            my $via = $property_data->{'via'};
            my $via_property_data = $instance_properties->{$via};
            unless ($via_property_data) {
                Carp::croak "Property $class_name '$property_name' filters '$via', but there is no property '$via'.";
            }
            
            $property_data->{'data_type'} = $via_property_data->{'data_type'};
            $property_data->{'reverse_as'} = $via_property_data->{'reverse_as'};
            if ($via_property_data->{'where'}) {
                unshift @{$property_data->{'where'}}, @{$via_property_data->{'where'}};
            }
        }
    }

    # allow parent classes to adjust the description in systematic ways 
    my $desc = \%new_class;
    unless ($bootstrapping) {
        for my $parent_class_name (@{ $new_class{is} }) {
            my $parent_class = $parent_class_name->__meta__;
            $desc = $parent_class->_preprocess_subclass_description($desc);
        }
    }

    my $meta_class_name = __PACKAGE__->_resolve_meta_class_name_for_class_name($class_name);
    $desc->{meta_class_name} ||= $meta_class_name;
    return $desc;
}

sub _normalize_property_description {
    my $class = shift;
    my $property_name = shift;
    my $property_data = shift;
    my $class_data = shift || $class;
    my $class_name = $class_data->{class_name};
    my %old_property = %$property_data;
    my %new_class = %$class_data;
    
    if (ref($old_property{id_by}) eq 'HASH') {
        $DB::single = 1;    
    }
    
    delete $old_property{source};

    if ($old_property{implied_by} and $old_property{implied_by} eq $property_name) {
        $class->warning_message("Cleaning up odd self-referential 'implied_by' on $class_name $property_name");
        delete $old_property{implied_by};
    }        

    # Only 1 of is_abstract, is_concrete or is_final may be set
    { no warnings 'uninitialized';
      if (  $old_property{is_abstract} 
          + $old_property{is_concrete}
          + $old_property{is_final}
          > 1
      ) {
          Carp::confess("abstract/concrete/final are mutually exclusive.  Error in class definition for $class_name property $property_name!");
      }
    }
    
    my %new_property = (
        class_name => $class_name,
        property_name => $property_name,
        type_name => $new_class{type_name},
    );
    
    for my $mapping (
        [ property_type                   => qw/resolution/],
        [ class_name                      => qw//],
        [ property_name                   => qw//],
        [ type_name                       => qw//],
        [ attribute_name                  => qw//],
        [ column_name                     => qw/sql/],
        [ constraint_name                 => qw//],
        [ data_length                     => qw/len/],
        [ data_type                       => qw/type is isa is_a/],
        [ default_value                   => qw/default value/],
        [ valid_values                    => qw//],
        [ doc                             => qw/description/],
        [ is_optional                     => qw/is_nullable nullable optional/],
        [ is_transient                    => qw//],
        [ is_volatile                     => qw//],
        [ is_constant                     => qw//], 
        [ is_class_wide                   => qw//], 
        [ is_delegated                    => qw//],
        [ is_calculated                   => qw//],
        [ is_mutable                      => qw//],
        [ is_transactional                => qw//], 
        [ is_abstract                     => qw//], 
        [ is_concrete                     => qw//], 
        [ is_final                        => qw//], 
        [ is_many                         => qw//],
        [ is_deprecated                   => qw//],
        [ is_numeric                      => qw//],
        [ is_id                           => qw//],
        [ id_by                           => qw//], 
        [ id_class_by                     => qw//],
        [ specify_by                      => qw//],
        [ order_by                        => qw//],
        [ via                             => qw//], 
        [ to                              => qw//],             
        [ where                           => qw/restrict filter/],
        [ implied_by                      => qw//],             
        [ calculate                       => qw//], 
        [ calculate_from                  => qw//],            
        [ calculate_perl                  => qw/calc_perl/],
        [ calculate_sql                   => qw/calc_sql/],
        [ calculate_js                    => qw//],
        [ reverse_as                      => qw/reverse_id_by im_its/],
        [ is_legacy_eav                   => qw//],
        [ is_dimension                    => qw//],
        [ is_specified_in_module_header   => qw//],
        [ position_in_module_header       => qw//],
        [ singular_name                   => qw//],
        [ plural_name                     => qw//],
    ) {
        my ($primary_field_name, @alternate_field_names) = @$mapping;
        my @all_fields = ($primary_field_name, @alternate_field_names);
        my @values = grep { defined($_) } delete @old_property{@all_fields};
        if (@values > 1) {
            Carp::confess(
                "Multiple values in class definition for $class_name for field "
                . join("/", @all_fields)
            );
        }
        elsif (@values == 1) {
            $new_property{$primary_field_name} = $values[0];
        }
        if (
            (not exists $new_property{$primary_field_name}) 
            and 
            (exists $UR::Object::Property::defaults{$primary_field_name}) 
        ) {
            $new_property{$primary_field_name} = $UR::Object::Property::defaults{$primary_field_name};
        }
    }

    if (my $data = delete $old_property{delegate}) {
        if ($data->{via} =~ /^eav_/ and $data->{to} eq 'value') {
            $new_property{is_legacy_eav} = 1;
        }
        else {
            die "Odd delegation for $property_name: " 
                . Data::Dumper::Dumper($data);
        }
    }
    
    if ($new_property{data_type}) {
        if (my ($length) = ($new_property{data_type} =~ /\((\d+)\)$/)) {
            $new_property{data_length} = $length;
            $new_property{data_type} =~ s/\(\d+\)$//;
        }
    }
    
    if (grep { $_ ne 'is_calculated' && /calc/ } keys %new_property) {
        $new_property{is_calculated} = 1;
    }

    
    if ($new_property{via} 
        || $new_property{to} 
        || $new_property{id_by} 
        || $new_property{reverse_as}         
    ) {
        $new_property{is_delegated} = 1;
        unless (defined $new_property{to}) {
            $new_property{to} = $property_name;
        }
    }
    
    if (!defined($new_property{is_mutable})) {
        if ($new_property{is_delegated}
               or
             (defined $class_data->{'subclassify_by'} and $class_data->{'subclassify_by'} eq $property_name)
        ) {
            $new_property{is_mutable} = 0;
        }
        else {
            $new_property{is_mutable} = 1;
        }
    }

    # For classes that have (or pretend to have) tables, the Property objects
    # should get their column_name property automatically filled in
    my $the_data_source;
    if (ref($new_class{'data_source_id'}) eq 'HASH') {
        # This is an inline-defined data source
        $the_data_source = $new_class{'data_source_id'}->{'is'};
    } elsif ($new_class{'data_source_id'}) {
        $the_data_source = $new_class{'data_source_id'};
        $the_data_source = UR::DataSource->get($the_data_source) || $the_data_source->get();
    }
    # UR::DataSource::File-backed classes don't have table_names, but for querying/saving to
    # work property, their properties still have to have column_name filled in
    if (($new_class{table_name} or ($the_data_source and ($the_data_source->initializer_should_create_column_name_for_class_properties())))
        and not exists($new_property{column_name})
        and not $new_property{is_transient}
        and not $new_property{is_delegated}
        and not $new_property{is_calculated}
        and not $new_property{is_legacy_eav}
    ) {
        $new_property{column_name} = $new_property{property_name};            
    }
    $new_property{column_name} = uc($new_property{column_name}) if ($new_property{column_name});
    
    unless ($new_property{attribute_name}) {
        $new_property{attribute_name} = $property_name;
        $new_property{attribute_name} =~ s/_/ /g;
    }

    if (my $extra = $class_data->{attributes_have}) {
        my @names = keys %$extra;
        @new_property{@names} = delete @old_property{@names};
    }

    if ($new_property{order_by} and not $new_property{is_many}) {
        die "Cannot use order_by except on is_many properties!";
    }

    if ($new_property{specify_by} and not $new_property{is_many}) {
        die "Cannot use specify_by except on is_many properties!";
    }

    if (my @unknown = keys %old_property) {
        Carp::confess("unknown meta-attributes present for $class_name $property_name: @unknown\n");
    }

    if ($new_property{implied_by} and $new_property{implied_by} eq $property_name) {
        $class->warnings_message("New data has odd self-referential 'implied_by' on $class_name $property_name!");
        delete $new_property{implied_by};
    }        

    if (ref($new_property{id_by}) eq 'HASH') {
        $DB::single = 1;    
    }
    
    
    return %new_property;
}

sub _make_minimal_class_from_normalized_class_description {
    my $class = shift;
    my $desc = shift;
   
    my $class_name = $desc->{class_name};
    unless ($class_name) {
        Carp::confess("No class name specified?");
    }
    
    my $meta_class_name = $desc->{meta_class_name};
    die unless $meta_class_name;
    if ($meta_class_name ne __PACKAGE__) {
        unless (
            $meta_class_name->isa(__PACKAGE__)
        ) {
            warn "Bogus meta class $meta_class_name doesn't inherit from UR::Object::Type?"
        }
    }
    
    # only do this when the classes match
    # when they do not match, the super-class has already called this by delegating to the correct subclass
    $class_name::VERSION = 2.0;

    my $self =  bless { id => $class_name, %$desc }, $meta_class_name;
    
    $UR::Context::all_objects_loaded->{$meta_class_name}{$class_name} = $self;
    my $full_name = join( '::', $class_name, '__meta__' );
    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => '__meta__',
        code => Sub::Name::subname $full_name => sub {$self},
    });

    return $self;
}

sub _initialize_accessors_and_inheritance {  
    my $self = shift;
    
    $self->initialize_direct_accessors;
    
    my $class_name = $self->{class_name};

    my @is = @{ $self->{is} };
    unless (@is) {
        @is = ('UR::ModuleBase') 
    }
    eval "\@${class_name}::ISA = (" 
        . join(',', map { "'$_'" } @is) . ")\n";
    Carp::confess($@) if $@;
        
    return $self;
}

our %_inform_all_parent_classes_of_newly_loaded_subclass;
sub _inform_all_parent_classes_of_newly_loaded_subclass {
    my $self = shift;    
    my $class_name = $self->class_name;
    
    if ($class_name eq 'Genome::Model::Command::Ghost') {
    #    print Carp::longmess();
    }
    Carp::confess("re-initializing class $class_name") if $_inform_all_parent_classes_of_newly_loaded_subclass{$class_name};
    $_inform_all_parent_classes_of_newly_loaded_subclass{$class_name} = 1;    
    
    no strict 'refs';
    no warnings;
    my @parent_classes = @{ $class_name . "::ISA" };
    for my $parent_class (@parent_classes) {
        unless ($parent_class->can("id")) {
            __PACKAGE__->use_module_with_namespace_constraints($parent_class);
            if ($@) {
                die "Failed to find parent_class $parent_class for $class_name!";
            }
        }
    }
    
    my @i = sort $class_name->inheritance;
    $UR::Object::_init_subclasses_loaded{$class_name} ||= [];
    my $last_parent_class = "";
    for my $parent_class (@i) {
        next if $parent_class eq $last_parent_class;
        $last_parent_class = $parent_class;
        $UR::Object::_init_subclasses_loaded{$parent_class} ||= [];
        push @{ $UR::Object::_init_subclasses_loaded{$parent_class} }, $class_name;
        push @{ $parent_class . "::_init_subclasses_loaded" }, $class_name;
        
        # any index on a parent class must move to the child class
        # if the child class were loaded before the index is made, it is pushed down at index creation time
        if (my $parent_index_hashrefs = $UR::Object::Index::all_by_class_name_and_property_name{$parent_class}) {
            #print "PUSHING INDEXES FOR $parent_class to $class_name\n";
            for my $parent_property (keys %$parent_index_hashrefs) {
                my $parent_indexes = $parent_index_hashrefs->{$parent_property};
                my $indexes = $UR::Object::Index::all_by_class_name_and_property_name{$class_name}{$parent_property} ||= [];
                push @$indexes, @$parent_indexes;
            }
        }
    }
    
    return 1;
}

sub _complete_class_meta_object_definitions {
    my $self = shift;        
    my $class = $self->{class_name};

    # track related objects
    my @subordinate_objects;

    # grab some data from the object
    my $class_name = $self->{class_name};
    my $type_name = $self->{type_name};
    my $table_name = $self->{table_name};    
    
    # decompose the embedded complex data structures into normalized objects
    my $inheritance = $self->{is};
    my $properties = $self->{has};
    my $relationships = $self->{relationships} || [];
    my $constraints = $self->{constraints};
    my $data_source = $self->{'data_source_id'};

    my $id_properties = $self->{id_by};
    my %id_property_rank;
    for (my $i = '0 but true'; $i < @$id_properties; $i++) {
        $id_property_rank{$id_properties->[$i]} = $i;
    }
    
    # mark id/non-id properites
    foreach my $pinfo ( values %$properties ) {
        $pinfo->{'is_id'} = $id_property_rank{$pinfo->{'property_name'}};
    }
    
    # handle inheritance
    unless ($class_name eq "UR::Object") {
        no strict 'refs';

        # sanity check
        my @expected = @$inheritance;
        my @actual =  @{ $class_name . "::ISA" };

        if (@actual and "@actual" ne "@expected") {
            Carp::confess("for $class_name: expected '@expected' actual '@actual'\n");
        }

        # set
        @{ $class_name . "::ISA" } = @$inheritance;
    }

    # Create inline data source
    if ($data_source and ref($data_source) eq 'HASH') {
        $self->{'__inline_data_source_data'} = $data_source;
        my $ds_class = $data_source->{'is'};
        my $inline_ds = $ds_class->create_from_inline_class_data($self, $data_source);
        $self->{'data_source_id'} = $self->{'db_committed'}->{'data_source_id'} = $inline_ds->id;
    }

    for my $parent_class_name (@$inheritance) {
        my $parent_class = $parent_class_name->__meta__;
        unless ($parent_class) {
            $DB::single = 1;
            $parent_class = $parent_class_name->__meta__;
            $self->error_message("Failed to find parent class $parent_class_name\n");
            return;
        }
        
        unless(ref($parent_class) and $parent_class->can('type_name')) {            
            print Data::Dumper::Dumper($parent_class);
            $DB::single = 1;
            redo;
        }
        
        if (not defined $self->schema_name) {
            if (my $schema_name = $parent_class->schema_name) {
                $self->{'schema_name'} = $self->{'db_committed'}->{'schema_name'} = $schema_name;
            }
        }

        if (not defined $self->data_source_id) {
            if (my $data_source_id = $parent_class->data_source_id) {
                $self->{'data_source_id'} = $self->{'db_committed'}->{'data_source_id'} = $data_source_id;
            }
        }

        # If a parent is declared as a singleton, we are too.
        # This only works for abstract singletons.
        if ($parent_class->is_singleton and not $self->is_singleton) {
            $self->is_singleton($parent_class->is_singleton);
        }
    }
    
    # when we "have" an object reference, add it to the list of old-style references
    # also ensure the old-style property definition is complete
    for my $pinfo (grep { $_->{id_by} } values %$properties) {
        push @$relationships, $pinfo->{property_name}, $pinfo;
        
        my $id_properties = $pinfo->{id_by};
        my $r_class_name = $pinfo->{data_type};
        unless($r_class_name) {
            die sprintf("Object accessor property definition for %s::%s has an 'id_by' but no 'data_type'",
                                  $pinfo->{'class_name'}, $pinfo->{'property_name'});
        }
        my $r_class;        
        my @r_id_properties;
        
        for (my $n=0; $n<@$id_properties; $n++) {
            my $id_property_name = $id_properties->[$n];
            my $id_property_detail = $properties->{$id_property_name};
            unless ($id_property_detail) {
                $DB::single = 1;
                1;
            }
            unless ($id_property_detail->{data_type}) {
                unless ($r_class) {
                    # FIXME - it'd be nice if we didn't have to load the remote class here, and
                    # instead put off loading until it's necessary 
                    $r_class ||= UR::Object::Type->get($r_class_name);
                    unless ($r_class) {
                        Carp::confess("Unable to load $r_class_name while defining relationship ".$pinfo->{'property_name'}. " in class $class");
                    }
                    @r_id_properties = $r_class->id_property_names;
                }                
                my ($r_property) = 
                    map { 
                        my $r_class_ancestor = UR::Object::Type->get($_);
                        my $data = $r_class_ancestor->{has}{$r_id_properties[$n]};
                        ($data ? ($data) : ());
                    }
                    ($r_class_name, $r_class_name->__meta__->ancestry_class_names);
                unless ($r_property) {
                    $DB::single = 1;
                    my $property_name = $pinfo->{'property_name'};
                    if (@$id_properties != @r_id_properties) {
                        Carp::croak("Can't resolve relationship for class $class property '$property_name': "
                                    . "id_by metadata has " . scalar(@$id_properties) . " items, but remote class "
                                    . "$r_class_name only has " . scalar(@r_id_properties) . " ID properties\n");
                    } else {
                        my $r_id_property = $r_id_properties[$n] ? "'$r_id_properties[$n]'" : '(undef)';
                        Carp::croak("Can't resolve relationship for class $class property '$property_name': "
                                    . "Class $r_class_name does not have an ID property named $r_id_property, "
                                    . "which would be linked to the local property '".$id_properties->[$n]."'\n");
                    }
                }
                $id_property_detail->{data_type} = $r_property->{data_type};
            }
        }
        next;
    }
    
    # make old-style (bc4nf) property objects in the default way
    $type_name = $self->{type_name};
    my @property_objects;
    
    for my $pinfo (values %$properties) {                        
        my $property_name       = $pinfo->{property_name};
        my $property_subclass   = $pinfo->{property_subclass};
        
        # Acme::Employee::Attribute::Name is a bc6nf attribute
        # extends Acme::Employee::Attribute
        # extends UR::Object::Attribute
        # extends UR::Object
        my @words = map { ucfirst($_) } split(/_/,$property_name);
        #@words = $self->namespace->get_vocabulary->convert_to_title_case(@words);
        my $bridge_class_name = 
            $class_name 
            . "::Attribute::" 
            . join('', @words);
        
        # Acme::Employee::Attribute::Name::Type is both the class definition for the bridge,
        # and also the attribute/property metadata for 
        my $property_meta_class_name = $bridge_class_name . "::Type";

        # define a new class for the above, inheriting from UR::Object::Property
        # all of the "attributes_have" get put into the class definition
        # call the constructor below on that new class       
        #UR::Object::Type->__define__(
        ##    class_name => $property_meta_class_name,
        #    is => 'UR::Object::Property', # TODO: go through the inheritance 
        #    has => [
        #        @{ $class_name->__meta__->{attributes_have} }
        #    ]
        #)
 
        my ($singular_name,$plural_name);
        unless ($pinfo->{plural_name} and $pinfo->{singular_name}) {
            require Lingua::EN::Inflect;
            if ($pinfo->{is_many}) {
                $plural_name = $pinfo->{plural_name} ||= $pinfo->{property_name};
                $pinfo->{singular_name} = Lingua::EN::Inflect::PL_V($plural_name);
            }
            else {                
                $singular_name = $pinfo->{singular_name} ||= $pinfo->{property_name};
                $pinfo->{plural_name} = Lingua::EN::Inflect::PL($singular_name);
            }
        }

        my $property_object = UR::Object::Property->__define__(%$pinfo, id => $class_name . "\t" . $property_name);
        
        unless ($property_object) {
            $self->error_message("Error creating property $property_name for class " . $self->class_name . ": " . $class->error_message);
            for $property_object (@subordinate_objects) { $property_object->unload }
            $self->unload;
            return;
        }
        
        push @property_objects, $property_object;
        push @subordinate_objects, $property_object;
    }

    if ($constraints) {
        my $property_rule_template = UR::BoolExpr::Template->resolve('UR::Object::Property','class_name','property_name');

        my $n = 1;
        for my $unique_set (sort { $a->{sql} cmp $b->{sql} } @$constraints) {
            my ($name,$properties,$group,$sql);
            if (ref($unique_set) eq "HASH") {
                $name = $unique_set->{name};
                $properties = $unique_set->{properties};
                $sql = $unique_set->{sql};
                $name ||= $sql;
            }
            else {
                $properties = @$unique_set;
                $name = $type_name . "_$n";
                $n++;
            }
            for my $property_name (sort @$properties) {
                my $prop_rule = $property_rule_template->get_rule_for_values($class_name,$property_name);
                my $property = $UR::Context::current->get_objects_for_class_and_rule('UR::Object::Property', $prop_rule);
                unless ($property) {
                    Carp::croak("Constraint '$name' on class $class_name requires unknown property '$property_name'");
                }
            }
        }
    }

    for my $obj ($self,@subordinate_objects) {
        #use Data::Dumper;
        no strict;
        my %db_committed = %$obj;
        delete @db_committed{@keys_to_delete_from_db_committed};
        $obj->{'db_committed'} = \%db_committed;
            
    };

    unless ($self->generate) {    
        $self->error_message("Error generating class " . $self->class_name . " as part of creation : " . $self->error_message);
        for my $property_object (@subordinate_objects) { $property_object->unload }
        $self->unload;
        return;
    }

    if (my $extra = $self->{extra}) {
        # some class characteristics may be only present in subclasses of UR::Object
        # we handle these at this point, since the above is needed for boostrapping
        $DB::single = 1 if keys %$extra;
        my %still_not_found;
        for my $key (sort keys %$extra) {
            if ($self->can($key)) {
                $self->$key($extra->{$key});
            }
            else {
                $still_not_found{$key} = $extra->{$key};
            }
        }
        if (%still_not_found) {
            Carp::confess("BAD CLASS DEFINITION for $class_name.  Unrecognized properties: " . Data::Dumper::Dumper(%still_not_found));
        }
    }

    $self->__signal_change__("load");

    # The inheritance method is high overhead because of the number of times it is called.
    # Cache on a per-class basis.
    my @i = $class_name->inheritance;
    if (grep { $_ eq '' } @i) {
        print "$class_name! @{ $self->{is} }";
        $DB::single = 1;
        $class_name->inheritance;
    }
    Carp::confess("Odd inheritance @i for $class_name") unless $class_name->isa('UR::Object');
    my $src1 = " return shift->SUPER::inheritance(\@_) if ( (ref(\$_[0])||\$_[0]) ne '$class_name');  return (" . join(", ", map { "'$_'" } (@i)) . ")";
    my $src2 = qq|sub ${class_name}::inheritance { $src1 }|;
    eval $src2  unless $class_name eq 'UR::Object';
    die $@ if $@;

    # return the new class object
    return $self;
}

# write the module from the existing data in the class object
sub generate {
    my $self = shift;
    return 1 if $self->{'generated'};

    #my %params = @_;   # Doesn't seem to be used below...


    # The follwing code will override a lot intentionally.
    # Supress the warning messages.
    no warnings;

    # the class that this object represents
    # the class that we're going to generate
    # the "new class"
    my $class_name = $self->class_name;

    # this is done earlier in the class definition process in _make_minimal_class_from_normalized_class_description()
    my $full_name = join( '::', $class_name, '__meta__' );
    Sub::Install::reinstall_sub({
        into => $class_name,
        as   => '__meta__',
        code => Sub::Name::subname $full_name => sub {$self},
    });

    my @parent_class_names = $self->parent_class_names;
    
    do {
        no strict 'refs';
        if (@{ $class_name . '::ISA' }) {
            #print "already have isa for class_name $class_name: " . join(",",@{ $class_name . '::ISA' }) . "\n";
        }
        else {
            no strict 'refs';
            @{ $class_name . '::ISA' } = @parent_class_names;
            #print "setting isa for class_name $class_name: " . join(",",@{ $class_name . '::ISA' }) . "\n";
        };
    };


    my ($props, $cols) = ([], []);  # for _all_properties_columns()    
    $self->{_all_properties_columns} = [$props, $cols];
    
    my $id_props = [];              # for _all_id_properties()    
    $self->{_all_id_properties} = $id_props;    
        
    # build the supplemental classes
    for my $parent_class_name (@parent_class_names) {
        next if $parent_class_name eq "UR::Object";

        if ($parent_class_name eq $class_name) {
            Carp::confess("$class_name has parent class list which includes itself?: @parent_class_names\n");
        }

        my $parent_class_meta = UR::Object::Type->get(class_name => $parent_class_name);
        
        unless ($parent_class_meta) {
            $DB::single = 1;
            $parent_class_meta = UR::Object::Type->get(class_name => $parent_class_name);
            Carp::confess("Cannot generate $class_name: Failed to find class meta-data for base class $parent_class_name.");
        }
        
        unless ($parent_class_meta->generated()) {            
            $parent_class_meta->generate();
        }
        
        unless ($parent_class_meta->{_all_properties_columns}) {
            Carp::confess("No _all_properties_columns for $parent_class_name?");
        }
        
        # inherit properties and columns
        my ($p, $c) = @{ $parent_class_meta->{_all_properties_columns} };
        push @$props, @$p if $p;
        push @$cols, @$c if $c;
        my $id_p = $parent_class_meta->{_all_id_properties};
        push @$id_props, @$id_p if $id_p;
    }


    # set up accessors/mutators for properties
    my @property_objects =
        UR::Object::Property->get(class_name => $self->class_name);

    my @id_property_objects = $self->direct_id_property_metas;
    my %id_property;
    for my $ipo (@id_property_objects) {
        $id_property{$ipo->property_name} = 1;
    }

    if (@id_property_objects) {
        $id_props = [];
        for my $ipo (@id_property_objects) {
            push @$id_props, $ipo->property_name;
        }
    }

    my $has_table;
    my @parent_classes = map { UR::Object::Type->get(class_name => $_) } @parent_class_names;
    for my $co ($self, @parent_classes) {
        if ($co->table_name) {
            $has_table = 1;
            last;
        }
    }
    
    for my $property_object (sort { $a->property_name cmp $b->property_name } @property_objects) {
        #if ($property_object->column_name or not $has_table) {
        if ($property_object->column_name) {
            push @$props, $property_object->property_name;
            push @$cols, $property_object->column_name;
        }    
    }

    # set the flag to prevent this from occurring multiple times.
    $self->generated(1);

    # read in filesystem package if there is one
    #$self->use_filesystem_package($class_name);

    # Let each class in the inheritance hierarchy do any initialization
    # required for this class.  Note that the _init_subclass method does
    # not call SUPER::, but relies on this code to find its parents.  This
    # is the only way around a sparsely-filled multiple inheritance tree.

    # TODO: Replace with $class_name->EVERY::LAST::_init_subclass()

    #unless (
    #    $bootstrapping
    #    and 
    #    $UR::Object::_init_subclass->{$class_name}
    #) 
    {
        my @inheritance = $class_name->inheritance;
        my %done;
        for my $parent (reverse @inheritance) {
            my $initializer = $parent->can("_init_subclass");
            next unless $initializer;
            next if $done{$initializer};
            $initializer->($class_name,$class_name)
                    or die "Parent class $parent failed to initialize subclass "
                        . "$class_name :" . $parent->error_message;
            $done{$initializer} = 1;
        }
    }
    
    unless ($class_name->isa("UR::Object")) {
        print Data::Dumper::Dumper('@C::ISA',\@C::ISA,'@B::ISA',\@B::ISA);
    }

    # ensure the class is generated
    die "Error in module for $class_name.  Resulting class does not appear to be generated!" unless $self->generated;

    # ensure the class inherits from UR::Object
    die "$class_name does not inherit from UR::Object!" unless $class_name->isa("UR::Object");

    return 1;
}


1;


