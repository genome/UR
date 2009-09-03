package UR::Object;
#sub define { shift->__define__(@_) }

use warnings;
use strict;

require UR;

use Scalar::Util;

our @ISA = ('UR::ModuleBase');
our $VERSION = $UR::VERSION;;

sub class { ref($_[0]) || $_[0] }

sub __meta__  {
    # subclasses set this specifically for efficiency
    # the base class has a generic implementation for boostrapping
    my $class_name = shift;
    return $UR::Context::all_objects_loaded->{"UR::Object::Type"}{$class_name};
}

sub __label_name__ {
    # This is typically set in derived classes to the "entity name".
    # As a fallback we just use the class.
    my $self = $_[0];
    my $class = ref($self) || $self;
    my ($label) = ($class =~ /([^:]+)$/);
    $label =~ s/([a-z])([A-Z])/$1 $2/g;
    $label =~ s/([A-Z])([A-Z]([a-z]|\s|$))/$1 $2/g;
    $label = uc($label) if $label =~ /_id$/i;
    return $label;
}

sub __display_name__ {
    my $self = shift;
    my $in_context_of_related_object = shift;
    
    my $name = $self->id;
    $name =~ s/\t/ /g;
    return $name;

    if (not $in_context_of_related_object) {
        # no in_context_of_related_object.
        # the object is identified globally
        return $self->label_name . ' ' . $name;
    }
    elsif ($in_context_of_related_object eq ref($self)) {
        # the class is completely known
        # show only the core display name
        # -> less text, more in_context_of_related_object
        return $name
    }
    else {
        # some intermediate base class is known,
        # TODO: make this smarter
        # For now, just show the whole class name with the ID
        return $self->label_name . ' ' . $name;
    }
}

sub context {
    # For efficiency, all context switches update this value.
    # We will ultimately need to support objects knowing their context explicitly
    # for things such as data maintenance operations.  TODO.
    $UR::Context::current;
}

sub define_boolexpr {
    return UR::BoolExpr->resolve(@_);
}

sub define_set {
    my $class = shift;
    $class = ref($class) || $class;
    my $rule = UR::BoolExpr->resolve($class,@_);
    my $set_class = $class . "::Set";
    return $set_class->get($rule->id);    
}

sub create_iterator {
    my $class = shift;
    my %params = @_;
    
    my $filter;
    if ($params{'where'}) {
        # old syntax
        $filter = delete $params{'where'};
    } else {
        # new syntax takes key => value params just like get()
        $filter = \@_;
    }
  
    unless (Scalar::Util::blessed($filter)) {
        $filter = UR::BoolExpr->resolve($class,@$filter)
    }
    
    my $iterator = UR::Object::Iterator->create_for_filter_rule($filter);
    unless ($iterator) {
        $class->error_message(UR::Object::Iterator->error_message);
        return;
    }
    
    return $iterator;    
}

sub create_viewer {
    my $self = shift;
    my $class = $self->class;

    my $viewer = UR::Object::Viewer->create_viewer(
        subject_class_name => $class,
        perspective => "default",
        @_
    );

    unless ($viewer) {
        $self->error_message("Error creating viewer: " . UR::Object::Viewer->error_message);
        return;
    }

    if (ref($self)) {
        $viewer->set_subject($self);
    }

    return $viewer;
}

# Handle weak references in the object cache.
sub DESTROY {
    my $obj = shift;

    # $destroy_should_clean_up_all_objects_loaded will be true if either light_cache is on, or
    # the cache_size_highwater mark is a valid value
    if ($UR::Context::destroy_should_clean_up_all_objects_loaded) {
        my $class = ref($obj);
        if ($obj->__meta__->is_meta_meta or $obj->__changes__) {
            my $obj_from_cache = delete $UR::Context::all_objects_loaded->{$class}{$obj->{id}};
            die "Object found in all_objects_loaded does not match destroyed ref/id! $obj/$obj->{id}!" unless $obj eq $obj_from_cache;
            $UR::Context::all_objects_loaded->{$class}{$obj->{id}} = $obj;
            print "KEEPING $obj.  Found $obj .\n";
            return;
        }
        else {
            if ($ENV{'UR_DEBUG_OBJECT_RELEASE'}) {
                print STDERR "MEM DESTROY object $obj class ",$obj->class," id ",$obj->id,"\n";
            }
            $obj->unload();
            return $obj->SUPER::DESTROY();
        }
    }
    else {
        if ($ENV{'UR_DEBUG_OBJECT_RELEASE'}) {
            print STDERR "MEM DESTROY object $obj class ",$obj->class," id ",$obj->id,"\n";
        }
        $obj->SUPER::DESTROY();
    }
};

# Turn off monitoring of the DESTROY handler at application exit.
END {
    # setting the typeglob to undef does not work. -sms
    delete $UR::Object::{DESTROY};
};


# Mark this object as unloadable by the object cache pruner.
#
# If the class has a data source, then a weakened object is dropped
# at the first opportunity, reguardless of its __get_serial number.
# For classes without a data source, then it will be dropped according to
# the normal rules w/r/t the __get_serial (classes without data sources
# normally are never dropped by the pruner)
sub __weaken__ {
    my $self = $_[0];
    delete $self->{'__strengthened'};
    $self->{'__weakened'} = 1;
}

# Indicate this object should never be unloaded by the object cache pruner
sub __strengthen__ {
    my $self = $_[0];
    delete $self->{'__weakened'};
    $self->{'__strengthened'} = 1;
}


# Base object API 
    
sub create {
    my $class = shift;        
    
    my $class_meta = $class->__meta__;        
    
    # Few different ways for automagic subclassing...

    # #1 - The class specifies that we should call this other method (sub_classification_method_name)
    # to determine the correct subclass
    if (my $method_name = $class_meta->first_sub_classification_method_name) {
        my($rule, %extra) = UR::BoolExpr->resolve_normalized($class, @_);
        my $sub_class_name = $class->$method_name(@_);
        if (defined($sub_class_name) and ($sub_class_name ne $class)) {
            # delegate to the sub-class to create the object
            no warnings;
            unless ($sub_class_name->can('create')) {
                $DB::single = 1;
                print $sub_class_name->can('create');
                die "$class has determined via $method_name that the correct subclass for this object is $sub_class_name.  This class cannot create!" . join(",",$sub_class_name->inheritance);
            }
            return $sub_class_name->create(@_);
        }
        # fall through if the class names match
    }

    # #2 - The class create() was called on is abstract and has a subclassify_by property named.
    # Extract the value of that property from the rule to determine the subclass create() should 
    # really be called on
    if ($class_meta->is_abstract) {
        my($rule, %extra) = UR::BoolExpr->resolve_normalized($class, @_);

        # Determine the correct subclass for this object
        # and delegate to that subclass.
        my $subclassify_by = $class_meta->subclassify_by;
        if ($subclassify_by) {
            unless ($rule->specifies_value_for($subclassify_by)) {
                if ($class_meta->is_abstract) {
                    Carp::confess(
                        "Invalid parameters for $class create():"
                        . " abstract class requires $subclassify_by to be specified"
                        . "\nParams were: " . Data::Dumper::Dumper({ $rule->params_list })
                    );               
                }
                else {
                    ($rule, %extra) = UR::BoolExpr->resolve_normalized($class, $subclassify_by => $class, @_);
                    unless ($rule and $rule->specifies_value_for($subclassify_by)) {
                        die "Error setting $subclassify_by to $class!";
                    }
                } 
            }           
            my $sub_class_name = $rule->value_for($subclassify_by);
            unless ($sub_class_name) {
                die "no sub class found?!";
            }
            if ($sub_class_name eq $class) {
                die "sub-classified as its own class $class!";
            }
            unless ($sub_class_name->isa($class)) {
                die "class $sub_class_name is not a sub-class of $class!"; 
            }
            return $sub_class_name->create(@_); 
        }
        else {
            Carp::confess("$class requires support for a 'type' class which has persistance.  Broken.  Fix me.");
            #my $params = $rule->legacy_params_hash;
            #my $sub_classification_meta_class_name = $class_meta->sub_classification_meta_class_name;
            # there is some other class of object which typifies each of the subclasses of this abstract class
            # let that object tell us the class this object goes into
            #my $type = $sub_classification_meta_class_name->get($type_id);
            #unless ($type) {
            #    Carp::confess(
            #        "Invalid parameters for $class create():"
            #        . "Failed to find a $sub_classification_meta_class_name"
            #        . " with identifier $type_id."
            #    );
            #}
            #my $subclass_name = $type->subclass_name($class);
            #unless ($subclass_name) {
            #    Carp::confess(
            #        "Invalid parameters for $class create():"
            #        . "$sub_classification_meta_class_name '$type_id'"
            #        . " failed to return a s sub-class name for $class"
            #    );
            #}
            #return $subclass_name->create(@_);
        }

    }

    # Normal case... just make a rule out of the passed-in params
    my $rule = UR::BoolExpr->resolve_normalized($class, @_);

    # Process parameters.  We do this here instead of 
    # waiting for _create_object to do it so that we can ensure that
    # we have an ID, and autogenerate an ID if necessary.
    my $params = $rule->legacy_params_hash;
    my $id = $params->{id};        

    # Whenever no params, or a set which has no ID, make an ID.
    unless (defined($id)) {            
        $id = $class_meta->autogenerate_new_object_id($rule);
        unless (defined($id)) {
            $class->error_message("No ID for new $class!\n");
            return;
        }
    }
    
    # @extra is extra values gotten by inheritance
    my @extra;
    
    # %property_objects maps property names to UR::Object::Property objects
    # by going through the reversed list of UR::Object::Type objects below
    # We set up this hash to have the correct property objects for each property
    # name.  This is important in the case of property name overlap via
    # inheritance.  The property object used should be the one "closest"
    # to the class.  In other words, a property directly on the class gets
    # used instead of an inherited one.
    my %property_objects;
    my %direct_properties;
    my %indirect_properties; 
    my %set_properties;
    my %default_values;
    my %immutable_properties;
    
    for my $co ( reverse( $class_meta, $class_meta->ancestry_class_metas ) ) {
        # Reverse map the ID into property values.
        # This has to occur for all subclasses which represent table rows.
        
        my @id_property_names = $co->id_property_names;
        my @values = $co->resolve_ordered_values_from_composite_id( $id );
        $#values = $#id_property_names;
        push @extra, map { $_ => shift(@values) } @id_property_names;
        
        # deal with %property_objects
        my @property_objects = $co->direct_property_metas;
        my @property_names = map { $_->property_name } @property_objects;
        @property_objects{@property_names} = @property_objects;            
        
        foreach my $prop ( @property_objects ) {
            my $name = $prop->property_name;
            $default_values{ $prop->property_name } = $prop->default_value if (defined $prop->default_value);
            if ($prop->is_many) {
                $set_properties{$name} = $prop;
            }
            elsif ($prop->is_indirect) {
                $indirect_properties{$name} = $prop;
            }
            else {
                $direct_properties{$name} = $prop;
            }
            
            unless ($prop->is_mutable) {
                $immutable_properties{$name} = 1;
            }
        }
    }
    
    my @indirect_property_names = keys %indirect_properties;
    my @direct_property_names = keys %direct_properties;

    $params = { %$params };

    my $indirect_values = {}; # collection of key-value pairs for the EAV table
    for my $property_name (keys %indirect_properties) {
        $indirect_values->{ $property_name } =
            delete $params->{ $property_name }
                if ( exists $params->{ $property_name } );
    }

    my $set_values = {};
    for my $property_name (keys %set_properties) {
        $set_values->{ $property_name } =
            delete $params->{ $property_name }
                if ( exists $params->{ $property_name } );
    }
    
    # create the object.
    my $self = $class->_create_object(%default_values, %$params, @extra, id => $id);
    unless ($self) {
        return;
    }

    # add itesm for any multi properties
    if (%$set_values) {
        for my $property_name (keys %$set_values) {
            my $meta = $set_properties{$property_name};
            my $singular_name = $meta->singular_name;
            my $adder = 'add_' . $singular_name;
            my $value = $set_values->{$property_name};
            unless (ref($value) eq 'ARRAY') {
                die "odd non-array refrenced used for 'has-many' property $property_name for $class: $value!";
            }
            for my $item (@$value) {
                if (ref($item) eq 'ARRAY') {
                    $self->$adder(@$item);
                }
                elsif (ref($item) eq 'HASH') {
                    $self->$adder(%$item);
                }
                else {
                    $self->$adder($item);
                }
            }
        }
    }    

    # set any indirect properties        
    if (%$indirect_values) {
        for my $property_name (keys %$indirect_values) {
            $self->$property_name($indirect_values->{$property_name});
        }
    }

    if (%immutable_properties) {
        my @problems = $self->__errors__();
        if (@problems) {
            my @errors_fatal_to_construction;
            
            my %problems_by_property_name;
            for my $problem (@problems) {
                my @problem_properties;
                for my $name ($problem->properties) {
                    if ($immutable_properties{$name}) {
                        push @problem_properties, $name;                        
                    }
                }
                if (@problem_properties) {
                    push @errors_fatal_to_construction, join(" and ", @problem_properties) . ': ' . $problem->desc;
                }
            }
            
            if (@errors_fatal_to_construction) {
                my $msg = 'Failed to create ' . $class . ' with invalid immutable properties:'
                    . join("\n", @errors_fatal_to_construction);
                #$self->_delete_object;
                #die $msg;
            }
        }
    }
    
    $self->__signal_change__("create");
    return $self;
}

sub delete {
    my $self = shift;

    if (ref($self)) {
        # Delete the specified object.
        if ($self->{db_committed} || $self->{db_saved_uncommitted}) {

            # gather params for the ghost object
            my $do_data_source;
            my %ghost_params;
            my @pn;
            { no warnings 'syntax';
               @pn = grep { $_ ne 'data_source_id' || ($do_data_source=1 and 0) } # yes this really is '=' and not '=='
                     grep { exists $self->{$_} }
                     $self->__meta__->all_property_names;
            }
            
            # we're not really allowed to interrogate the data_source property directly
            @ghost_params{@pn} = $self->get(@pn);
            if ($do_data_source) {
                $ghost_params{'data_source_id'} = $self->{'data_source_id'};
            }    

            # create ghost object
            my $ghost = $self->ghost_class->_create_object(id => $self->id, %ghost_params);
            unless ($ghost) {
                $DB::single = 1;
                Carp::confess("Failed to constructe a deletion record for an unsync'd delete.");
            }
            $ghost->__signal_change__("create");

            for my $com (qw(db_committed db_saved_uncommitted)) {
                $ghost->{$com} = $self->{$com}
                    if $self->{$com};
            }

        }
        $self->__signal_change__('delete');
        $self->_delete_object;
        return $self;
    }
    else {
        Carp::confess("Can't call delete as a class method.");
    }
}

sub _create_object {
    my $class = shift;
 
    #my $params = { $class->define_bx(@_)->params_list };
    my $params = $class->preprocess_params(@_);

    my $id = $params->{id};
    unless (defined($id)) {
        Carp::confess(
            "No ID specified (or incomplete id params) for $class _create_object.  Params were:\n" 
            . Dumper($params)
        );
    }

    # Ensure that we're not remaking things which exist.
    if ($UR::Context::all_objects_loaded->{$class}->{$id}) {
        # The object exists.  This is not an exception for some reason?  
        # We just return false to indicate that the object is not creatable.
        $class->error_message("An object of class $class already exists with id value '$id'");
        return;
    }

    # get rid of internal flags (which start with '-')
    delete $params->{$_} for ( grep { /^_/ } keys %$params );

    # TODO: The reference to UR::Entity can be removed when non-tablerow classes impliment property function for all critical internal data.
    # Make the object.
    my $self = bless {
        map { $_ => $params->{$_} }
        grep { $class->can($_) or not $class->isa('UR::Entity') }
        keys %$params
    }, $class;

    # See if we're making something which was previously deleted and is pending save.
    # We must capture the old db_committed data to ensure eventual saving is done correctly.
    if (my $ghost = $UR::Context::all_objects_loaded->{$class . "::Ghost"}->{$id}) {	
        # Note this object's database state in the new object so saves occurr correctly,
        # as an update instead of an insert.
        if (my $committed_data = $ghost->{db_committed})
        {
            $self->{db_committed} = { %$committed_data };
        }

        if (my $unsaved_data = $ghost->{'db_saved_uncommitted'})
        {
            $self->{'db_saved_uncommitted'} = { %$unsaved_data };
        }
        $ghost->__signal_change__("delete");
        $ghost->_delete_object;
    }

    # Put the object in the master repository of objects for the application.
    $UR::Context::all_objects_loaded->{$class}->{$id} = $self;

    # If we're using a light cache, weaken the reference.
    if ($UR::Context::light_cache and substr($class,0,5) ne 'App::') {
        Scalar::Util::weaken($UR::Context::all_objects_loaded->{$class}->{$id});
    }

    # Return the new object.
    return $self;
}

sub _delete_object {
    my $self = $_[0];
    my $class = $self->class;
    my $id = $self->id;

    if ($self->{'__get_serial'}) {
        # Keep a correct accounting of objects.  This one is getting deleted by a method
        # other than UR::Context::prune_object_cache
        $UR::Context::all_objects_cache_size--;
    }

    # Remove the object from the main hash.
    delete $UR::Context::all_objects_loaded->{$class}->{$id};
    delete $UR::Context::all_objects_are_loaded->{$class};

    # Decrement all of the param_keys it is using.
    if ($self->{load} and $self->{load}->{param_key})
    {
        while (my ($class,$param_strings_hashref) = each %{ $self->{load}->{param_key} })
        {
            for my $param_string (keys %$param_strings_hashref) {
                delete $UR::Context::all_params_loaded->{$class}->{$param_string};

                foreach my $local_apl ( values %$UR::Context::object_fabricators ) {
                    next unless ($local_apl and exists $local_apl->{$class});
                    delete $local_apl->{$class}->{$param_string};
                }
            }
        }
    }

    # Turn our $self reference into a UR::DeletedRef.
    # Further attempts to use it will result in readable errors.
    # The object can be resurrected.
    if ($ENV{'UR_DEBUG_OBJECT_RELEASE'}) {
        print STDERR  "MEM DELETE object $self class ",$self->class," id ",$self->id,"\n";
    }
    UR::DeletedRef->bury($self);

    return $self;
}

sub __define__ {
    # This is to "virtually load" things.
    # Simply assert they already existed externally, and act as though they were just loaded...

    my $class = shift;
    my $class_meta = $class->__meta__;    
    if (my $method_name = $class_meta->sub_classification_method_name) {
        my($rule, %extra) = UR::BoolExpr->resolve_normalized($class, @_);
        my $sub_class_name = $class->$method_name(@_);
        if ($sub_class_name ne $class) {
            # delegate to the sub-class to create the object
            return $sub_class_name->define(@_);
        }
    }

    my $self = $class->_create_object(@_);
    return unless $self;
    $self->{db_committed} = { %$self };
    $self->__signal_change__("load");
    return $self;
}


sub get {
    # Fast optimization for the default case.
    {
        no warnings;
        if (exists $UR::Context::all_objects_loaded->{$_[0]}
            and my $obj = $UR::Context::all_objects_loaded->{$_[0]}->{$_[1]}
            )
        {
            $obj->{'__get_serial'} = $UR::Context::GET_COUNTER++;
            return $obj;
        }
    };

    # Normal logic for finding objects smartly is below.

    my $class = shift;

    # Handle the case in which this is called as an object method.
    # Functionality is completely different.

    if(ref($class)) {
        my @rvals;
        foreach my $prop (@_) {
            push(@rvals, $class->$prop());
        }

        if(wantarray) {
            return @rvals;
        }
        else {
            return \@rvals;
        }
    }
    
    my ($rule, @extra) = UR::BoolExpr->resolve($class,@_);        
    
    if (@extra) {
        # remove this and have the developer go to the datasource 
        if (scalar @extra == 2 and $extra[0] eq "sql") {
            return $UR::Context::current->_get_objects_for_class_and_sql($class,$extra[1]);
        }
        
        # keep this part: let the sub-class handle special params if it can
        return $class->get_with_special_parameters($rule, @extra);
    }

    # This is here for bootstrapping reasons: we must be able to load class singletons
    # in order to have metadata for regular loading....
    if (!$rule->has_meta_options and ($class->isa("UR::Object::Type") or $class->isa("UR::Singleton") or $class->isa("UR::Value"))) {
        my $normalized_rule = $rule->normalize;
        
        my @objects = $class->_load($normalized_rule);
        
        return unless defined wantarray;
        return @objects if wantarray;
        
        if ( @objects > 1 and defined(wantarray)) {
            my $params = $rule->params_list();
            $DB::single=1;
            print "Got multiple matches for class $class\nparams were: ".join(', ', map { "$_ => " . $params->{$_} } keys %$params) . "\nmatched objects were:\n";
            foreach my $o (@objects) {
               print "Object $o\n";
               foreach my $k ( keys %$o) {
                   print "$k => ".$o->{$k}."\n";
               }
            }
            Carp::confess("Multiple matches for $class query!". Data::Dumper::Dumper([$rule->params_list]));
            Carp::confess("Multiple matches for $class, ids: ",map {$_->id} @objects, "\nParams: ",
                           join(', ', map { "$_ => " . $params->{$_} } keys %$params)) if ( @objects > 1 and defined(wantarray));
        }
        
        return $objects[0];
    }

    return $UR::Context::current->get_objects_for_class_and_rule($class, $rule);
}

sub get_with_special_parameters {
    my $class = shift;
    my $rule = shift;        
    Carp::confess(
        "Unknown parameters to $class get().  "
        . "Implement get_with_special_parameters() to handle non-standard"
        . " (non-property) query options.\n"
        . "The special params were " 
        . Dumper(\@_)
        . "Rule ID: " . $rule->id . "\n"
    );
}

sub get_or_create {
    my $self = shift;
    return $self->get( @_ ) || $self->create( @_ );
}

sub set  {
    my $self = shift;
    my @rvals;

    while (@_) {
        my $property_name = shift;
        my $value = shift;
        push(@rvals, $self->$property_name($value));
    }

    if(wantarray) {
        return @rvals;
    }
    else {
        return \@rvals;
    }
}

sub property_diff {
    # Ret hashref of the differences between the object and some other object.
    # The "other object" may be a hashref or hash, in which case it will
    # treat each key as a property.

    my ($self, $other) = @_;
    my $diff = {};

    # If we got a hash instead of a hashref...
    if (@_ > 2)
    {
        shift;
        $other = { @_ }
    }

    no warnings;
    my $self_value;
    my $other_value;
    my $class_object = $self->__meta__;
    for my $property ($class_object->all_property_names)
    {
        if (ref($other) eq 'HASH')
        {
            next unless exists $other->{$property};
            $other_value = $other->{$property};
        }
        else
        {
            $other_value = $other->$property;
        }
        $self_value = $self->$property;
        $diff->{$property} = $self_value if ($other_value ne $self_value);
    }
    return $diff;
}

sub __changes__ {
    # This is really never overridden in subclasses.
    # Return attributes for all changes.
    my ($self,$optional_property) = @_;
    
    return unless $self->{_change_count};
    #print "changes on $self! $self->{_change_count}\n";
    my $meta = $self->__meta__;
    if (ref($meta) eq 'UR::DeletedRef') {
        print Data::Dumper::Dumper($self,$meta);
        Carp::confess("Meta is deleted for object requesting changes: $self\n");
    }
    if (!$meta->is_transactional and !$meta->is_meta_meta) {
        return;
    }

    my $orig = $self->{db_saved_uncommitted} || $self->{db_committed};

    no warnings;
    my @changed;
    if ($orig)
    {
        my $class_name = $meta->class_name;
        @changed =
            grep {
                my $property_meta = $meta->property_meta_for_name($_);
                ( ((!$property_meta) or $property_meta->is_transient) ? 0 : 1 );
            }
            grep { $self->can($_) and not UR::Object->can($_) }
            grep { $orig->{$_} ne $self->{$_} }
            grep { $_ }
            keys %$orig;
    }
    else
    {
        @changed = $meta->all_property_names
    }

    return map
    {
        UR::Object::Tag->create
        (
            type => 'changed',
            properties => [$_]
        )
    } @changed;
}

# This is the basis for software constraint checking.

sub __errors__ {
    my ($self,@property_names) = @_;

    my $class_object = $self->__meta__;
    my $type_name = $class_object->type_name;

    unless (scalar @property_names) {
        @property_names = $class_object->all_property_names;    
    }

    my @properties = map {
        $class_object->property_meta_for_name($_);
    } @property_names;

    my @tags;
    for my $property_metadata (@properties) {
        # For now we don't validate these.
        # Ultimately, we should delegate to the property metadata object for value validation.
        next if $property_metadata->is_delegated;
        next if $property_metadata->is_calculated;
        
        my $property_name = $property_metadata->property_name;
        
        my @values = $self->$property_name;
        next if @values > 1;
        my $value = $values[0];

        unless ($property_metadata->is_optional) {
            if (!defined $value) {
                push @tags, UR::Object::Tag->create(
                    type => 'invalid',
                    properties => [$property_name],
                    desc => "No value specified for required property $property_name."
                );                
            }
        }
        
        # The tests below don't apply do undefined values.
        # Save the trouble and move on.
        next unless defined $value;

        # Check data type
        my $generic_data_type = $property_metadata->generic_data_type || "";
        my $data_length       = $property_metadata->data_length;

        if ($generic_data_type eq 'Float') {
            $value =~ s/\s//g;
            $value = $value + 0;

            my $length =0;

            if($value =~ /^(\+|\-)?([0-9]+)(\.([0-9]*))?[eE](\+|\-)?(\d+)$/){ #-- scientific notation
                $length = length($2)-1 + $6 + (!$5 || $5 eq '+' ? 1 : 0);
            }
            elsif($value =~ /^(\+|\-)?([0-9]*)(\.([0-9]*))?$/) {
                # If the data type is specified as a Float, but really contains an int, then
                # $4 is undef causing a warning about "uninitialized value in concatenation",
                # but otherwise works OK
                no warnings 'uninitialized';
                $length = length($2.$4);
                --$length if $2 == 0 && $4;
            }
            else{
                push @tags, UR::Object::Tag->create
                (
                    type => 'invalid',
                    properties => [$property_name],
                    desc => 'Invalid decimal value.'
                );
            }
            # Cleanup for size check below.
            $value = '.' x $length;
        }
        elsif ($generic_data_type eq 'Integer') {
            $value =~ s/\s//g;
            $value = $value + 0;
            if ($value !~ /^(\+|\-)?[0-9]*$/)
            {
                push @tags, UR::Object::Tag->create
                (
                    type => 'invalid',
                    properties => [$property_name],
                    desc => 'Invalid integer.'
                );
            }
            # Cleanup for size check below.
            $value =~ s/[\+\-]//g;
        }
        elsif ($generic_data_type eq 'DateTime') {
            # This check is currently disabled b/c of time format irrecularities
            # We rely on underlying database constraints for real invalidity checking.
            # TODO: fix me
            if (1) {

            }
            elsif ($value =~ /^\s*\d\d\d\d\-\d\d-\d\d\s*(\d\d:\d\d:\d\d|)\s*$/) {
                # TODO more validation here for a real date.
            }
            else {
                push @tags, UR::Object::Tag->create (
                    type => 'invalid',
                    properties => [$property_name],
                    desc => 'Invalid date string.'
                );
            }
        }

        # Check size
        if ($generic_data_type ne 'DateTime') {
            if ( defined($data_length) and ($data_length < length($value)) ) {
                push @tags, 
                    UR::Object::Tag->create(
                        type => 'invalid',
                        properties => [$property_name],
                        desc => sprintf('Value too long (%s of %s has length of %d and should be <= %d).',
                                        $property_name,
                                        $self->$property_name,
                                        length($value),
                                        $data_length)
                    );
            }
        }

        # Check valid values if there is an explicit list
        if (my $constraints = $property_metadata->valid_values) {
            my $valid = 0;
            for my $valid_value (@$constraints) {
                no warnings; # undef == ''
                if ($value eq $valid_value) {
                    $valid = 1;
                    last;
                }
            }
            unless ($valid) {
                my $value_list = join(', ',@$constraints);
                push @tags,
                    UR::Object::Tag->create(
                        type => 'invalid',
                        properties => [$property_name],
                        desc => sprintf(
                                'The value %s is not in the list of valid values for %s.  Valid values are: %s',
                                $value,
                                $property_name,
                                $value_list
                            )
                    );
            }
        }

        # Check FK if it is easy to do.
        # TODO: This is a heavy weight check, and is disabled for performance reasons.
        # Ideally we'd check a foreign key value _if_ it was changed only, since
        # saved foreign keys presumably could not have been save if they were invalid.
        if (0) {
            my $r_class;
            unless ($r_class->get(id => $value)) {
                push @tags, UR::Object::Tag->create (
                    type => 'invalid',
                    properties => [$property_name],
                    desc => "$value does not reference a valid " . $r_class . '.'
                );
            }
        }
    }

    return @tags;
}

# Observer pattern
sub add_observer {
    my $self = shift;
    my %params = @_;
    my $observer = UR::Observer->create(
        subject_class_name => $self->class,
        subject_id => (ref($self) ? $self->id : undef),
        aspect => delete $params{aspect},
        callback => delete $params{callback}
    );  
    unless ($observer) {
        $self->error_message(
            "Failed to create observer: "
            . UR::Observer->error_message
        );
        return;
    }
    if (%params) {
        $observer->delete;
        die "Bad params for observer creation!: "
            . Data::Dumper::Dumper(\%params)
    }
    return $observer;
}

# TODO: move this into the context
our $sig_depth = 0;
sub __signal_change__ {
    my ($self, $property, @data) = @_;

    my ($class,$id);
    if (ref($self)) {
        $class = ref($self);
        $id = $self->id;
        unless ($property eq 'load' or $property eq 'define' or $property eq 'unload') {
            $self->{_change_count}++;
            #print "changing $self $property @data\n";    
        }
    }
    else {
        $class = $self;
        $self = undef;
        $id = undef;
    }

    if ($UR::Context::Transaction::log_all_changes) {
        # eventually all calls to __signal_change__ will go directly here
        UR::Context::Transaction->log_change($self, $class, $id, $property, @data);
    }

    if (my $index_list = $UR::Object::Index::all_by_class_name_and_property_name{$class}{$property}) {
        unless ($property eq 'create' or $property eq 'load' or $property eq 'define') {
            for my $index (@$index_list) {
                $index->_remove_object(
                    $self, 
                    { $property => $data[0] }
                ) 
            }
        }
        
        unless ($property eq 'delete' or $property eq 'unload') {
            for my $index (@$index_list) {
                $index->_add_object($self)
            }
        }
    }

    # Before firing signals, we must update indexes to reflect the change.
    # This is currently a standard callback.

    my @check_classes  =
        (
            $class
            ? (
                $class,
                (grep { $_->isa("UR::Object") } $class->inheritance),
                ''
            )
            : ('')
        );
    my @check_properties    = ($property    ? ($property, '')    : ('') );
    my @check_ids           = ($id          ? ($id, '')          : ('') );

    #my @per_class  = grep { defined $_ } @$all_change_subscriptions{@check_classes};
    #my @per_method = grep { defined $_ } map { @$_{@check_properties} } @per_class;
    #my @per_id     = grep { defined $_ } map { @$_{@check_ids} } @per_method;
    #my @matches = map { @$_ } @per_id;

    my @matches =
        map { @$_ }
        grep { defined $_ } map { @$_{@check_ids} }
        grep { defined $_ } map { @$_{@check_properties} }
        grep { defined $_ } @$UR::Context::all_change_subscriptions{@check_classes};

    return unless @matches;

    #Carp::cluck() unless UR::Object::Subscription->can("class");
    #my @s = UR::Object::Subscription->get(
    ##    monitor_class_name => \@check_classes,
    #    monitor_method_name => \@check_properties,
    #    monitor_id => \@check_ids,
    #);

    #print STDOUT "fire __signal_change__: class $class id $id method $property data @data -> \n" . join("\n", map { "@$_" } @matches) . "\n";

    $sig_depth++;
    do {
        no warnings;
        @matches = sort { $a->[2] <=> $b->[2] } @matches;
    };
    
    #print scalar(@matches) . " index matches\n";
    foreach my $callback_info (@matches)
    {
        my ($callback, $note) = @$callback_info;
        &$callback($self, $property, @data)
    }
    $sig_depth--;

    return scalar(@matches);
}

sub create_mock {
    my $class = shift;
    my %params = @_;
    my $self = Test::MockObject->new();
    my $subject_class_object = $class->__meta__;
    for my $class_object ($subject_class_object,$subject_class_object->ancestry_class_metas) {
        for my $property ($class_object->direct_property_metas) {
            my $property_name = $property->property_name;
            if ($property->is_delegated && !exists($params{$property_name})) {
                next;
            }
            if ($property->is_mutable || $property->is_calculated || $property->is_delegated) {
                my $sub = sub {
                    my $self = shift;
                    if (@_) {
                        if ($property->is_many) {
                            $self->{'_'. $property_name} = @_;
                        } else {
                            $self->{'_'. $property_name} = shift;
                        }
                    }
                    return $self->{'_'. $property_name};
                };
                $self->mock($property_name, $sub);
                if ($property->is_optional) {
                    if (exists($params{$property_name})) {
                        $self->$property_name($params{$property_name});
                    }
                } else {
                    unless (exists($params{$property_name})) {
                        if (defined($property->default_value)) {
                            $params{$property_name} = $property->default_value;
                        } else {
                            unless ($property->is_calculated) {
                                die 'Failed to provide value for required mutable property '. $property_name;
                            }
                        }
                    }
                    $self->$property_name($params{$property_name});
                }
            } else {
                unless (exists($params{$property_name})) {
                    if (defined($property->default_value)) {
                        $params{$property_name} = $property->default_value;
                    } else {
                        die 'Failed to provide value for required property '. $property_name;
                    }
                }
                if ($property->is_many) {
                    $self->set_list($property_name,$params{$property_name});
                } else {
                    $self->set_always($property_name,$params{$property_name});
                }
            }
        }
    }
    my @classes = ($class, $subject_class_object->ancestry_class_names);
    $self->set_isa(@classes);
    $UR::Context::all_objects_loaded->{$class}->{$self->id} = $self;
    return $self;
}

# This module implements the deprecated parts of the UR::Object API
require UR::ObjectDeprecated;

1;

