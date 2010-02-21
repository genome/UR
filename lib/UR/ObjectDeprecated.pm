package UR::Object;

# deprecated parts of the UR::Object API

use warnings;
use strict;

use Data::Dumper;
use Scalar::Util qw(blessed);

sub get_with_special_parameters {
    # When overridden, this allows a class to take non-properties as parameters
    # to get(), and handle loading in a special way.  Ideally this is handled by
    # a custom data source, or properties with smart definitions.
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

    # get rid of internal flags (which start with '-' or '_', unless it's a named property)
    #delete $params->{$_} for ( grep { /^_/ } keys %$params );
    my %subject_class_props = map {$_, 1}  ( $class->__meta__->all_property_type_names);
    delete $params->{$_} foreach ( grep { substr($_, 0, 1) eq '_' and ! $subject_class_props{$_} } keys %$params );

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

# TODO: make this a context operation
sub unload {
    my $proto = shift;
    my ($self, $class);
    ref $proto ? $self = $proto : $class = $proto;
    
    my $cx = $UR::Context::current;

    if ( $self ) {
        # object method

        # The only things which can be unloaded are things committed to
        # their database in the exact same state.  Everything else must
        # be reverted or deleted.
        return unless $self->{db_committed};
        if ($self->__changes__) {
            #warn "NOT UNLOADING CHANGED OBJECT! $self $self->{id}\n";
            return;
        }

        $self->__signal_change__('unload');
        if ($ENV{'UR_DEBUG_OBJECT_RELEASE'}) {
            print STDERR "MEM UNLOAD object $self class ",$self->class," id ",$self->id,"\n";
        }
        $self->_delete_object;
        return $self;
    }
    else {
        # class method

        # unload the objects in the class
        # where there are subclasses of the class
        # delegate to them

        my @unloaded;

        # unload all objects of this class
        for my $obj ($cx->all_objects_loaded_unsubclassed($class))
        {
            push @unloaded, $obj->unload;
        }

        # unload any objects that belong to any subclasses
        for my $subclass ($cx->subclasses_loaded($class))
        {
            push @unloaded, $subclass->unload;
        }

        # get rid of the param_key hash for this class
        # this specifically gets rid of any cache for
        # param_keys that returned 0 objects
        delete $UR::Context::all_params_loaded->{$class};

        return @unloaded;
    }
}

# TODO: replace internal calls to go right to the context method
sub is_loaded {
    # this is just here for backward compatability for external calls
    # get() now goes to the context for data
    
    # This shortcut handles the most common case rapidly.
    # A single ID is passed-in, and the class name used is
    # not a super class of the specified object.
    # This logic is in both get() and is_loaded().

    my $quit_early = 0;
    if ( @_ == 2 &&  !ref($_[1]) ) {
        unless (defined($_[1])) {
            Carp::confess();
        }
        my $obj = $UR::Context::all_objects_loaded->{$_[0]}->{$_[1]};
        return $obj if $obj;
        # we could safely return nothing right now, except 
        # that a subclass of this type may have the object
    }

    my $class = shift;
    my $rule = UR::BoolExpr->resolve_normalized($class,@_);
    return $UR::Context::current->get_objects_for_class_and_rule($class,$rule,0);    
}

    
# THESE SHOULD PROBABLY GO ON THE CLASS META    

sub subclasses_loaded  {
    no strict 'refs';
    no warnings;    
    return @{ $UR::Object::_init_subclasses_loaded{$_[0]} };
}

sub all_objects_are_loaded  {
    # Keep track of which classes claim that they are completely loaded, and that no more loading should be done.
    # Classes which have the above function return true should set this after actually loading everything.
    # This class will do just that if it has to load everything itself.

    my $class = shift;
    #$meta = $class->__meta__;
    if (@_) {
        # Setting the attribute
        $UR::Context::all_objects_are_loaded->{$class} = shift;
    } elsif (! exists $UR::Context::all_objects_are_loaded->{$class}) {
        # unknown... ask the parent classes and remember the answer
        foreach my $parent_class ( $class->inheritance ) {
            if (exists $UR::Context::all_objects_are_loaded->{$parent_class}) {
                $UR::Context::all_objects_are_loaded->{$class} = $UR::Context::all_objects_are_loaded->{$parent_class};
                last;
            }
        }
    }
    return $UR::Context::all_objects_are_loaded->{$class};
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

    # Record amd return the subscription.
    no warnings;
    push @{ $UR::Context::all_change_subscriptions->{$class}->{$method}->{$id} }, [$callback,$note,$priority];
    return [$class,$id,$method,$callback,$note];
}

sub validate_subscription
{
    my ($self,$subscription_property) = @_;

    Carp::confess("The _create_object and _delete_object signals are no longer emitted!") 
        if defined($subscription_property) 
            and ($subscription_property eq '_create_object' or $subscription_property eq '_delete_object');

    # Undefined attributes indicate that the subscriber wants any changes at all to generate a callback.
    return 1 if (!defined($subscription_property));

    # All standard creation and destruction methods emit a signal.
    return 1 if ($subscription_property =~ /^(_create_object|_delete_object|create|delete|commit|rollback|load|unload|load_external)$/);

    # A defined attribute in our property list indicates the caller wants callbacks from our properties.
    my $class_object = $self->__meta__;
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
    # This can be removed when the __signal_change__ method uses inheritance.

    $class = undef if ($class eq __PACKAGE__);

    # Look for the callback

    $class = '' if not defined $class;
    $property = '' if not defined $property;
    $id = '' if not defined $id;

    my $arrayref = $UR::Context::all_change_subscriptions->{$class}->{$property}->{$id};
    return unless $arrayref;   # This thing didn't have a subscription in the first place
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

            #print STDOUT Dumper($UR::Context::all_change_subscriptions);

            if (@$arrayref == 0)
            {
                $arrayref = undef;

                delete $UR::Context::all_change_subscriptions->{$class}->{$property}->{$id};

                if (keys(%{ $UR::Context::all_change_subscriptions->{$class}->{$property} }) == 0)
                {
                    delete $UR::Context::all_change_subscriptions->{$class}->{$property};
                }
            }

            #print STDOUT Dumper($UR::Context::all_change_subscriptions);

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

# This should go away when we shift to fully to a transaction log for deletions.

sub ghost_class {
    my $class = $_[0]->class;
    $class = $class . '::Ghost';
    return $class;
}


# Old things still use this directly, sadly.

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
        my ($rule, @extra) = $class->can("define_boolexpr")->($class,@_);
        my $normalized_rule = $rule->normalize;
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


