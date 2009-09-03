
package UR::Object;

use warnings;
use strict;

#with 'UR::Module';      
use UR::ModuleBase;
our @ISA = ('UR::ModuleBase');

our $VERSION = '0.01';

use UR::DeletedRef;
use Data::Dumper;
use Scalar::Util qw(blessed);

sub class { ref($_[0]) || $_[0] }

sub get_class_object {
    # for bootstrapping
    # subclasses set this specifically for efficiency
    my $class_name = shift;
    return $UR::Object::all_objects_loaded{"UR::Object::Type"}{$class_name};
}

sub get_data_source {
    my $self = shift;
    return $UR::Context::current->resolve_data_source_for_object($self);
}

*get_rule_for_params = \&get_boolexpr_for_params;
 
sub get_boolexpr_for_params {
    return UR::BoolExpr->resolve_for_class_and_params(@_);
}

sub get_object_set {
    my $class = shift;
    my $rule = $class->get_rule_for_params(@_);
    my $set_class = $class . "::Set";
    return $set_class->get($rule->id);    
}

sub create_iterator {
    my $class = shift;
    my %params = @_;
    
    my $filter = delete $params{where};
    unless (blessed($filter)) {
        $filter = $class->get_rule_for_params(@$filter)
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

# These live in UR::Context, where they may switch to point to 
# different data structures depending on sub-context, transaction, etc.

# They are aliased here for backward compatability, since many parts 
# of the system use $UR::Object::whatever to work with them directly.

our ($all_objects_loaded, $all_change_subscriptions, $all_objects_are_loaded, $all_params_loaded);

*all_objects_loaded         = \$UR::Context::all_objects_loaded;
*all_change_subscriptions   = \$UR::Context::all_change_subscriptions;
*all_objects_are_loaded     = \$UR::Context::all_objects_are_loaded;
*all_params_loaded          = \$UR::Context::all_params_loaded;


# Handle weak references in the object cache.

sub DESTROY {
    my $obj = shift;
    if ($UR::Context::light_cache) {
        my $class = ref($obj);
        if ($class->isa("UR::Singleton") or $obj->get_class_object->is_meta or $obj->get_class_object->is_meta_meta or $obj->changed) {
            my $obj = delete $UR::Object::all_objects_loaded->{$class}{$obj->{id}};
            die "Object found in all_objects_loaded does not match destroyed ref/id! $obj/$obj->{id}!" unless $obj eq $obj;
            $UR::Object::all_objects_loaded->{$class}{$obj->{id}} = $obj;
            #print "KEEPING $obj.  Found $obj .\n";
            return;
        }
        else {
            delete $UR::Object::all_objects_loaded->{$class}{$obj->{id}};
            #$obj = delete $UR::Object::all_objects_loaded->{$class}{$obj->{id}};
            #print "TOSSING $obj.  Found $obj .\n";
            return $obj->SUPER::DESTROY();
        }
    }
    else {
        $obj->SUPER::DESTROY();
    }
};

# Turn off monitoring of the DESTROY handler at application exit.

END {
    # setting the typeglob to undef does not work. -sms
    delete $UR::Object::{DESTROY};
};


# BASE ::Object API
    
sub create {
    my $class = shift;        
    
    my $class_meta = $class->get_class_object;        
    
    if (my $method_name = $class_meta->first_sub_classification_method_name) {
        my($rule, %extra) = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($class, @_);
        my $sub_class_name = $class->$method_name(@_);
        if (defined($sub_class_name) and ($sub_class_name ne $class)) {
            # delegate to the sub-class to create the object
            unless ($sub_class_name->can('create')) {
                $DB::single = 1;
                print $sub_class_name->can('create');
                die "$class has determined via $method_name that the correct subclass for this object is $sub_class_name.  This class cannot create!" . join(",",$sub_class_name->inheritance);
            }
            return $sub_class_name->create(@_);
        }
        # fall through if the class names match
    }
    
    if ($class_meta->is_abstract) {
        my($rule, %extra) = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($class, @_);

        # Determine the correct subclass for this object
        # and delegate to that subclass.
        my $sub_classification_property_name = $class_meta->sub_classification_property_name;
        unless ($sub_classification_property_name) {
             Carp::confess("$class is abstract, but cannot dynamically resolve an appropriate subclass.");
        }
        unless ($rule->specifies_value_for_property_name($sub_classification_property_name)) {
            Carp::confess(
                "Invalid parameters for $class create():"
                . " abstract class requires $sub_classification_property_name to be specified"
                . "\nParams were: " . Data::Dumper::Dumper({ $rule->params_list })
            );                
        }            
        my $params = $rule->legacy_params_hash;
        my $type_id = $params->{$sub_classification_property_name};
        my $sub_classification_meta_class_name = $class_meta->sub_classification_meta_class_name;
        # there is some other class of object which typifies each of the subclasses of this abstract class
        # let that object tell us the class this object goes into
        my $type = $sub_classification_meta_class_name->get($type_id);
        unless ($type) {
            Carp::confess(
                "Invalid parameters for $class create():"
                . "Failed to find a $sub_classification_meta_class_name"
                . " with identifier $type_id."
            );
        }
        my $subclass_name = $type->subclass_name($class);
        unless ($subclass_name) {
            Carp::confess(
                "Invalid parameters for $class create():"
                . "$sub_classification_meta_class_name '$type_id'"
                . " failed to return a s sub-class name for $class"
            );
        }
        return $subclass_name->create(@_);
    }
    
    my $rule = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($class, @_);

    # Process parameters.  We do this here instead of 
    # waiting for create_object to do it so that we can ensure that
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
    my @direct_property_names;
    my %default_values;
    
    for my $co ( reverse( $class_meta, $class_meta->get_inherited_class_objects ) ) {
        # Reverse map the ID into property values.
        # This has to occur for all subclasses which represent table rows.
        
        my @id_property_names = $co->id_property_names;
        my @values = $co->class_name->decomposed_id( $id );
        $#values = $#id_property_names;
        push @extra, map { $_ => shift(@values) } @id_property_names;
        
        # deal with %property_objects
        my @property_objects = $co->get_property_objects;
        my @property_names = map { $_->property_name } @property_objects;
        @property_objects{@property_names} = @property_objects;            
        
        foreach my $prop ( @property_objects ) {
            $default_values{ $prop->property_name } = $prop->default_value if (defined $prop->default_value);
        }
                    
        #%property_objects = (
        #    %property_objects,
        #    map { $_->property_name => $_ }
        #    $co->get_property_objects
        #);
        
        if ($class_meta->isa("UR::Entity")) {
            # Things with a data source need a mapping to actually store
            # their value on the object. The rest will get EAVs.
            # Todo: store the EAVs here too.
            push @direct_property_names,
                map { $_->property_name } 
                grep { 
                    ($co->table_name and $_->column_name)
                    or 
                    ((not $co->table_name) and (not $_->column_name))
                }
                @property_objects;            
        }
        else {
            # Non data-sources store everything here, 
            # so we don't have to hassle with the other objects.
            push @direct_property_names, @property_names;
        }
    }
    
    my %indirect_properties = %property_objects;
    delete @indirect_properties{@direct_property_names};
    
    $params = { %$params };
    my $kv = {}; # collection of key-value pairs for the EAV table
    for my $property_name (keys %indirect_properties) {
        $kv->{ $property_name } =
            delete $params->{ $property_name }
                if ( exists $params->{ $property_name } );
    }
    
    # Create the object.
    
    my $self = $class->create_object(%default_values, %$params, @extra, id => $id);
    unless ($self) {
        return;
    }
    
    # set any attribute_value properties        
    if (%$kv) {
        for my $property_name ( keys %$kv )
        {
            my $po = $class_meta->get_property_object( property_name => $property_name );
            my $eav = GSC::EntityAttributeValue->create
            (
                type_name      => $po->type_name,
                entity_id      => $id,
                attribute_name => $po->attribute_name,
                value          => $kv->{ $property_name },
            );
        }
    }
    
    $self->signal_change("create");
    return $self;    
}

sub delete {
    my $self = shift;

    if (ref($self)) {
        # Delete the specified object.
        if ($self->{db_committed} || $self->{db_saved_uncommitted}) {

            # gather params for the ghost object
            my %ghost_params;
            my @pn = grep { exists $self->{$_} } $self->property_names;
            @ghost_params{@pn} = $self->get(@pn);

            # create ghost object
            my $ghost = $self->ghost_class->create_object(id => $self->id, %ghost_params);
            unless ($ghost) {
                $DB::single = 1;
                Carp::confess("Failed to constructe a deletion record for an unsync'd delete.");
            }
            $ghost->signal_change("create");

            for my $com (qw(db_committed db_saved_uncommitted)) {
                $ghost->{$com} = $self->{$com}
                    if $self->{$com};
            }

        }
        $self->signal_change('delete');
        $self->delete_object;
        return $self;
    }
    else {
        Carp::confess("Can't call delete as a class method.");
    }
}

sub create_object {
    my $class = shift;
 
    no warnings;
    my $params = $class->preprocess_params(@_);
    use warnings;

    my $id = $params->{id};
    unless (defined($id))
    {
        $DB::single = 1;
        $params = $class->preprocess_params(@_);
        Carp::confess(
            "No ID specified (or incomplete id params) for $class create_object.  Params were:\n" 
            . Dumper($params)
        );
    }

    # Ensure that we're not remaking things which exist.
    if ($all_objects_loaded->{$class}->{$id})
    {
        # The object exists.
        # This is not an error.  We just return false to indicate
        # That the object is not creatable.
        $class->error_message("An object of class $class already exists with id value '$id'");
        return;
    }

    # get rid of internal flags (which start with '_')
    delete $params->{$_} for ( grep { /^_/ } keys %$params );

    # TODO: The reference to UR::Entity can be removed when non-tablerow classes impliment property function for all critical internal data.
    # Make the object.
    my $self = bless
    {
        map { $_ => $params->{$_} }
        grep { $class->can($_) or not $class->isa('UR::Entity') }
        keys %$params
    }, $class;

    # See if we're making something which was previously deleted and is pending save.
    # We must capture the old db_committed data to ensure eventual saving is done correctly.
    if (my $ghost = $all_objects_loaded->{$class . "::Ghost"}->{$id})
    {	
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
        $ghost->signal_change("delete");
        $ghost->delete_object;
    }

    # Put the object in the master repository of objects for the application.
    $all_objects_loaded->{$class}->{$id} = $self;

    # If we're using a light cache, weaken the reference.
    if ($UR::Context::light_cache and substr($class,0,5) ne 'App::') {
        Scalar::Util::weaken($all_objects_loaded->{$class}->{$id});
    }

    # Return the new object.
    return $self;
}

sub delete_object {
    my $self = $_[0];
    my $class = $self->class;
    my $id = $self->id;

    # Remove the object from the main hash.
    # Setting undef instead of doing delete shortens later searches.
    delete $all_objects_loaded->{$class}->{$id};
    delete $all_objects_are_loaded->{$class};

    # Decrement all of the param_keys it is using.
    if ($self->{load} and $self->{load}->{param_key})
    {
        while (my ($class,$param_strings_hashref) = each %{ $self->{load}->{param_key} })
        {
            for my $param_string (keys %$param_strings_hashref) {
                delete $UR::Object::all_params_loaded->{$class}->{$param_string};
            }
        }
    }

    # Turn our $self reference into a UR::DeletedRef.
    # Further attempts to use it will result in readable errors.
    # The object can be resurrected.
    UR::DeletedRef->bury($self);

    return $self;
}

sub define {
    # This is to "virtually load" things.
    # Simply assert they already existed externally, and act as though they were just loaded...

    my $class = shift;
    my $class_meta = $class->get_class_object;    
    if (my $method_name = $class_meta->sub_classification_method_name) {
        my($rule, %extra) = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($class, @_);
        my $sub_class_name = $class->$method_name(@_);
        if ($sub_class_name ne $class) {
            # delegate to the sub-class to create the object
            return $sub_class_name->define(@_);
        }
    }
    
    my $self = $class->create_object(@_);
    return unless $self;
    $self->{db_committed} = { %$self };
    $self->signal_change("load");
    return $self;
}

sub load {
    # this is here for backward external compatability
    # get() now goes directly to the context
    
    my $class = shift;
    if (ref $class) {
         # Trying to reload a specific object?
         if (@_) {
             Carp::confess("load() on an instance with parameters is not supported");
             return;
         }
         @_ = ('id' ,$class->id());
         $class = ref $class;
    }

    my ($rule, @extra) = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($class,@_);        
    
    if (@extra) {
        if (scalar @extra == 2 and $extra[0] eq "sql") {
            return $UR::Context::current->_get_objects_for_class_and_sql($class,$extra[1]);
        }
        else {
            die "Odd parameters passed directly to $class load(): @extra.\n"
                . "Processable params were: "
                . Data::Dumper::Dumper({ $rule->params_list });
        }
    }
    return $UR::Context::current->get_objects_for_class_and_rule($class,$rule,1);
}

sub _load {
    Carp::cluck();
    my ($class,$rule) = @_;
    return $UR::Context::current->get_objects_for_class_and_rule($class,$rule,1);
}

sub unload {
    my $proto = shift;
    my ($self, $class);
    ref $proto ? $self = $proto : $class = $proto;

    if ( $self )
    {
        # object method

        # The only things which can be unloaded are things committed to
        # their database in the exact same state.  Everything else must
        # be reverted or deleted.
        return unless $self->{db_committed};
        if ($self->changed) {
            #warn "NOT UNLOADING CHANGED OBJECT! $self $self->{id}\n";
            return;
        }

        $self->signal_change('unload');
        $self->delete_object;
        return $self;
    }
    else
    {
        # class method

        # unload the objects in the class
        # where there are subclasses of the class
        # delegate to them

        my @unloaded;

        # unload all objects of this class
        for my $obj ($class->all_objects_loaded_unsubclassed)
        {
            push @unloaded, $obj->unload;
        }

        # unload any objects that belong to any subclasses
        for my $subclass ($class->subclasses_loaded)
        {
            push @unloaded, $subclass->unload;
        }

        # get rid of the param_key hash for this class
        # this specifically gets rid of any cache for
        # param_keys that returned 0 objects
        delete $UR::Object::all_params_loaded->{$class};

        return @unloaded;
    }
}

sub get {
    # Fast optimization for the default case.
    {
        no warnings;
        if (exists $all_objects_loaded->{$_[0]}
            and my $obj = $all_objects_loaded->{$_[0]}->{$_[1]}
            )
        {
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
    
    my ($rule, @extra) = UR::BoolExpr->resolve_for_class_and_params($class,@_);        
    
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
    if ($class->isa("UR::Object::Type") or $class->isa("UR::Singleton") or $class->isa("UR::Value")) {
        my $normalized_rule = $rule->get_normalized_rule_equivalent;
        
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
        "Unknown parameters to $class get()."
        . "Implement get_with_special_parameters() to handle non-standard"
        . " (non-property) query options.\n"
        . "The special params were " 
        . Dumper(\@_)
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

sub is_loaded {
    # this is just here for backward compatability for external calls
    # get() now goes to the context for data
    
    # This shortcut handles the most common case rapidly.
    # A single ID is passed-in, and the class name used is
    # not a super class of the specified object.
    # This logic is in both get() and is_loaded().

    if ( @_ == 2 &&  !ref($_[1]) )
    {
        unless (defined($_[1])) {
            Carp::confess();
        }
        my $obj = $all_objects_loaded->{$_[0]}->{$_[1]};
        return $obj if $obj;
    }

    my $class = shift;
    my $rule = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($class,@_);
    $UR::Context::current->get_objects_for_class_and_rule($class,$rule,0);    
}

sub _is_loaded {
    Carp::cluck();
    my ($class,$rule) = @_;
    return $UR::Context::current->get_objects_for_class_and_rule($class,$rule,0);
}
    

# THIS LOGIC PROBABLY GOES INTO THE CONTEXT

sub dbh {
    Carp::confess("Attempt to call dbh() on a UR::Object.\n" 
                  . "Objects no longer have DB handles, data_sources do\n"
                  . "use resolve_data_sources_for_class_meta_and_rule() on a UR::Context instead");
    my $ds = $UR::Context::current->resolve_data_sources_for_class_meta_and_rule(shift->get_class_object);
    return $ds->get_default_dbh;
}

sub db_committed { shift->{db_committed} }

sub db_saved_uncommitted { shift->{db_saved_uncommitted} }

# THESE SHOULD PROBABLY GO ON THE CLASS META    

sub subclasses_loaded  {
    no strict 'refs';
    no warnings;    
    return @{ $UR::Object::_init_subclasses_loaded{$_[0]} };
}

sub all_objects_loaded  {
    my $class = $_[0];
    return(
        grep {$_}
        map { values %{ $all_objects_loaded->{$_} } }
        $class, $class->subclasses_loaded
    );
}

sub all_objects_loaded_unsubclassed  {
    my $class = $_[0];
    return (grep {$_} values %{ $all_objects_loaded->{$class} } );
}

sub all_objects_are_loaded  {
    # Keep track of which classes claim that they are completely loaded, and that no more loading should be done.
    # Classes which have the above function return true should set this after actually loading everything.
    # This class will do just that if it has to load everything itself.

    my $class = shift;
    #$meta = $class->get_class_object;
    if (@_) {
        # Setting the attribute
        $all_objects_are_loaded->{$class} = shift;
    } elsif (! exists $all_objects_are_loaded->{$class}) {
        # unknown... ask the parent classes and remember the answer
        foreach my $parent_class ( $class->inheritance ) {
            if (exists $all_objects_are_loaded->{$parent_class}) {
                $all_objects_are_loaded->{$class} = $all_objects_are_loaded->{$parent_class};
                last;
            }
        }
    }
    return $all_objects_are_loaded->{$class};
}

# MOVE INTO VIEWER CLASSES

sub core_label_name {
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

sub _core_display_name {
    # This is an object-level fucntion to provide a freindly name for objects of this class.
    # It presumes that the type of the object need not be indicated in the name, just the identity within the class.
    my $name = $_[0]->id;
    $name =~ s/\t/ /g;
    return $name;
}

*label_name = \&core_label_name;

sub display_name {
    my $self = shift;
    my $context = shift;
    if (not $context)
    {
        # no context.
        # the object is identified globally
        return $self->label_name . ' ' . $self->_core_display_name;
    }
    elsif ($context eq ref($self))
    {
        # the class is completely known
        # show only the core display name
        # -> less text, more context
        return $self->_core_display_name
    }
    else
    {
        # some intermediate base class is known,
        # TODO: make this smarter
        # For now, just show the whole class name with the ID
        return $self->label_name . ' ' . $self->_core_display_name;
    }
}

# For backward compatability.
*display_name_full = \&display_name;

# For backward compatability.
sub display_name_brief {
    my $self = shift;
    $self->display_name(ref($self));
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
    my $class_object = $self->get_class_object;
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

sub changed {
    # This is really never overridden in subclasses.
    # Return attributes for all changes.
    my ($self,$optional_property) = @_;
    
    return unless $self->{_change_count};
    #print "changes on $self! $self->{_change_count}\n";
    my $meta = $self->get_class_object;
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
                my $property_meta = $meta->get_property_meta_by_name($_);
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

sub invalid {
    # For tablerow, we check data types and relationships,
    # and only for changed items, to save time.

    my ($self,@property_names) = @_;

    my $class_object = $self->get_class_object;
    my $type_name = $class_object->type_name;

    my @properties = UR::Object::Property->get
    (
        type_name => $type_name,
        (@property_names ? (property_name => \@property_names) : () )
    );


    my @tags;
    for my $property_metadata (@properties)
    {
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

        if ($generic_data_type eq 'Float')
        {
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
        elsif ($generic_data_type eq 'Integer')
        {
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
        elsif ($generic_data_type eq 'DateTime')
        {
            if (1)
            {

            }
            elsif ($value =~ /^\s*\d\d\d\d\-\d\d-\d\d\s*(\d\d:\d\d:\d\d|)\s*$/)
            {
                # TODO more validation here for a real date.
            }
            else
            {
                push @tags, UR::Object::Tag->create
                (
                    type => 'invalid',
                    properties => [$property_name],
                    desc => 'Invalid date string.'
                );
            }
        }

        # Check size
        if ($generic_data_type ne 'DateTime')
        {
            if ( defined($data_length) and ($data_length < length($value)) )
            {
                push @tags, UR::Object::Tag->create
                (
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

        # Check FK if it is easy to do.
        if (0)
        {
            my $r_class;
            # FIXME
            unless ($r_class->get(id => $value))
            {

                push @tags, UR::Object::Tag->create
                (
                    type => 'invalid',
                    properties => [$property_name],
                    desc => "$value does not reference a valid " . $r_class->label_name . '.'
                );
            }
        }
    }

    return @tags;
}

# Observer pattern (new)

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

# Observer pattern (old)

sub create_subscription  {
    my $self = shift;
    my %params = @_;

    # parse parameters
    my ($class,$id,$method,$callback,$note,$priority);
    $class = $self->class;
    $method = delete $params{method};
    $callback = delete $params{callback};
    $note = delete $params{note};
    $priority = delete $params{priority};
    unless (defined($priority)) {
        $priority = 1;
    }
    if (exists $params{id}) {
        $id = delete $params{id};
    }
    elsif (ref($self)) {
        $id = $self->id;
    }

    if (my @unknown = keys %params) {
        die "Unknown options @unknown passed to create_subscription!";
    }

    # print STDOUT "Caught subscription class $class id $id property $property callback $callback $note\n";

    # validate
    if (my @bad_params = %params) {
        die "Bad params passed to add_listener: @bad_params";
    }

    # Allow the class to know that it is getting a subscription.
    # It may choose to turn on/off optimizations depending on whether anyone is watching it.
    # It may also reject all subscriptions because it knows it is too busy to signal changes.
    unless($class->validate_subscription($method,$id,$callback)) {
        $DB::single = 1;
        $class->validate_subscription($method,$id,$callback);
        Carp::confess("Failed to validate requested subscription: @_\n");
        return 0; # If/when the above is removed.
    }

    # Handle global subscriptions.
    $class = undef if ($class eq __PACKAGE__);

    # This will not work currently because of a circular dep.
    # In the future, we'll have subscriptions be regular objects.

    #my $s = UR::Object::Subscription->create(
    #    monitor_class_name => $class,
    #    monitor_method_name => $method,
    #    monitor_id => $id,
    #    callback => $callback,
    #    note => $note,
    #    priority => $priority,
    #);
    #
    #unless ($s) {
    #    Carp::confess("Failed to create subscription @_");
    #}


    # Record amd return the subscription.
    no warnings;
    push @{ $all_change_subscriptions->{$class}->{$method}->{$id} }, [$callback,$note,$priority];
    return [$class,$id,$method,$callback,$note];
}

sub validate_subscription
{
    my ($self,$subscription_property) = @_;

    Carp::confess("The create_object and delete_object signals are no longer emitted!") 
        if defined($subscription_property) 
            and ($subscription_property eq 'create_object' or $subscription_property eq 'delete_object');

    # Undefined attributes indicate that the subscriber wants any changes at all to generate a callback.
    return 1 if (!defined($subscription_property));

    # All standard creation and destruction methods emit a signal.
    return 1 if ($subscription_property =~ /^(create_object|delete_object|create|delete|commit|rollback|load|unload|load_external)$/);

    # A defined attribute in our property list indicates the caller wants callbacks from our properties.
    my $class_object = $self->get_class_object;
    for my $property ($class_object->all_property_names)
    {
        return 1 if $property eq $subscription_property;
    }

    # Bad subscription request.
    return;
}

sub inform_subscription_cancellation
{
    # This can be overridden in derived classes if the class wants to know
    # when subscriptions are cancelled.
    return 1;
}

our $sig_depth = 0;
sub signal_change
{
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
        # eventually all calls to signal_change will go directly here
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
        grep { defined $_ } @$all_change_subscriptions{@check_classes};

    return unless @matches;

    #Carp::cluck() unless UR::Object::Subscription->can("class");
    #my @s = UR::Object::Subscription->get(
    ##    monitor_class_name => \@check_classes,
    #    monitor_method_name => \@check_properties,
    #    monitor_id => \@check_ids,
    #);

    #print STDOUT "fire signal_change: class $class id $id method $property data @data -> \n" . join("\n", map { "@$_" } @matches) . "\n";

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

sub cancel_change_subscription ($@)
{
    my ($class,$id,$property,$callback,$note);

    if (@_ >= 4)
    {
        ($class,$id,$property,$callback,$note) = @_;
        die "Bad parameters." if ref($class);
    }
    elsif ( (@_==3) or (@_==2) )
    {
        ($class, $property, $callback) = @_;
        if (ref($_[0]))
        {
            $class = ref($_[0]);
            $id = $_[0]->id;
        }
    }
    else
    {
        die "Bad parameters.";
    }

    # Handle global subscriptions.  Subscriptions to UR::Object affect all objects.
    # This can be removed when the signal_change method uses inheritance.

    $class = undef if ($class eq __PACKAGE__);

    # Look for the callback

    $class = '' if not defined $class;
    $property = '' if not defined $property;
    $id = '' if not defined $id;

    my $arrayref = $all_change_subscriptions->{$class}->{$property}->{$id};
    my $index = 0;

    while ($index <= @$arrayref)
    {
        my ($cancel_callback, $note) = @{ $arrayref->[$index] };

        if
        (
            (not defined($callback))
            or
            ($callback eq $cancel_callback)
            or
            ($note =~ $callback)
        )
        {
            # Remove the callback from the subscription list.

            my $found = splice(@$arrayref,$index,1);
            #die "Bad splice $found $index @$arrayref!" unless $found eq $arrayref->[$index];

            # Prune the $all_change_subscriptions hash tree.

            #print STDOUT Dumper($all_change_subscriptions);

            if (@$arrayref == 0)
            {
                $arrayref = undef;

                delete $all_change_subscriptions->{$class}->{$property}->{$id};

                if (keys(%{ $all_change_subscriptions->{$class}->{$property} }) == 0)
                {
                    delete $all_change_subscriptions->{$class}->{$property};
                }
            }

            #print STDOUT Dumper($all_change_subscriptions);

            # Tell the class that a subscription has been cancelled, if it cares
            # (most classes do not impliment this, and the default UR::Object version is ignored.

            unless($class->inform_subscription_cancellation($property,$id,$callback))
            {
                Carp::confess("Failed to validate requested subscription cancellation: @_\n");
                return 0; # If/when the above is removed.
            }

            # Return a ref to the callback removed.  This is "true", but better than true.

            return $found;
        }
        else
        {
            # Increment only if we did not splice-out a value.
            $index++;
        }
    }

    # Return nothing if we found no subscription.

    return;
}

# This should go away when we shift ot fully to a transaction log for deletions.

sub ghost_class {
    my $class = $_[0]->class;
    $class = $class . '::Ghost';
    return $class;
}


# KEEP FUNCTIONALITY, BUT RENAME/REFACTOR

sub generate_support_class {
    # A class Foo can implement this method to have a chance to auto-define Foo::Bar 
    # TODO: make a Class::Autouse::ExtendNamespace Foo => sub { } to handle this.
    # Right now, UR::ModuleLoader will try it after "use".
    my $class  = shift;
    my $ext = shift;
    my $class_meta = $class->get_class_object;
    return $class_meta->generate_support_class_for_extension($ext);
}

sub object_properties_as_hash {
    my %clone = %{ $_[0] };
    for my $key (keys %clone) {
        if ($key =~ /^_/
        ) {
            delete $clone{$key}
        }
    }
    delete $clone{db_committed};
    delete $clone{db_saved_uncommitted};
    delete $clone{load};
    return %clone;
}

sub matches {
    no warnings;
    my $self = shift;
    my %param = $self->preprocess_params(@_);
    for my $key (keys %param) {
        next unless $self->can($key);
        return 0 unless $self->$key eq $param{$key}
    }
    return 1;
}


# DEFINITELY REFACTOR AWAY
# All calls to these methods should go to the class meta object directly.

sub property_names {
    my $class = shift;
    my $meta = $class->get_class_object;
    return $meta->all_property_names;
}

sub load_all_on_first_access  {
    # For some objects, it is more efficient to load the whole set as soon as any are used.
    # Derived classes can override this when that is the case.

    my $self = shift;
    return () if $self->class eq "UR::Entity";
    my $type = $self->get_class_object;
    return unless $type;
    return ( (defined($type->er_role) and $type->er_role eq 'validation item') or ($type->class_name =~ /Type$/) ? 1 : 0);
}

sub _resolve_composite_id {
    return shift->get_class_object->resolve_composite_id_from_ordered_values(@_);
}

sub decomposed_id {
    return shift->get_class_object->resolve_ordered_values_from_composite_id(@_);
}

# Most code should go right to ->get_rule_for_params(), 
# which can return the same info as preprocessed params
# including a ->legacy_params_hash().

# Old things still use this directly, though.

sub preprocess_params {
    if (@_ == 2 and ref($_[1]) eq 'HASH') {
        # already processed, just throw it back to the caller
        if (wantarray) {
            # ... after flattening it out
            return %{ $_[1] };
        }
        else {
            # .. just the reference
            return $_[1];
        }
    }
    else {
        my $class = shift;
        $class = (ref($class)?ref($class):$class);

        # get the rule object, which has the old params pre-cached
        my ($rule, @extra) = $class->can("get_rule_for_params")->($class,@_);
        my $normalized_rule = $rule->get_normalized_rule_equivalent;
        my $rule_params = $normalized_rule->legacy_params_hash;

        # catch only case where sql is passed in
        if (@extra == 2 && $extra[0] eq "sql"
            && $rule_params->{_unique} == 0
            && $rule_params->{_none} == 1
            && (keys %$rule_params) == 2
        ) {

            push @extra,
                "_unique" => 0,
                "_param_key" => (
                    ref($extra[1])
                        ? join("\n", map { defined($_) ? "'$_'" : "undef"} @{$extra[1]})
                        : $extra[1]
                );

            if (wantarray) {
                return @extra;
            }
            else {
                return { @extra }
            }
        }

        if (wantarray) {
            # flatten out the cached params hash
            #return %{ $rule->{legacy_params_hash} };
            return %{ $rule_params }, @extra;
        }
        else {
            # duplicate the reference, and return the duplicate
            #return { %{ $rule->{legacy_params_hash} } };
            return { %{ $rule_params }, @extra };
        }
    }
}

1;

