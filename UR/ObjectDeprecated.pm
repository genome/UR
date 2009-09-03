package UR::Object;

# deprecated parts of the UR::Object API

use warnings;
use strict;

use Data::Dumper;
use Scalar::Util qw(blessed);

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
        if ($self->changed) {
            #warn "NOT UNLOADING CHANGED OBJECT! $self $self->{id}\n";
            return;
        }

        $self->signal_change('unload');
        $self->delete_object;
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
    my $rule = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($class,@_);
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

    Carp::confess("The create_object and delete_object signals are no longer emitted!") 
        if defined($subscription_property) 
            and ($subscription_property eq 'create_object' or $subscription_property eq 'delete_object');

    # Undefined attributes indicate that the subscriber wants any changes at all to generate a callback.
    return 1 if (!defined($subscription_property));

    # All standard creation and destruction methods emit a signal.
    return 1 if ($subscription_property =~ /^(create_object|delete_object|create|delete|commit|rollback|load|unload|load_external)$/);

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
    # This can be removed when the signal_change method uses inheritance.

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


# KEEP FUNCTIONALITY, BUT RENAME/REFACTOR

sub generate_support_class {
    # A class Foo can implement this method to have a chance to auto-define Foo::Bar 
    # TODO: make a Class::Autouse::ExtendNamespace Foo => sub { } to handle this.
    # Right now, UR::ModuleLoader will try it after "use".
    my $class  = shift;
    my $ext = shift;
    my $class_meta = $class->__meta__;
    return $class_meta->generate_support_class_for_extension($ext);
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


