package UR::Context;

use strict;
use warnings;
use Date::Parse;
use Sub::Name;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Context',    
    is_abstract => 1,
    has => [
        parent  => { is => 'UR::Context', id_by => 'parent_id', is_optional => 1 }
    ],
    doc => <<EOS
The environment in which oo-activity occurs in UR.  The current context represents the current state 
of everything.  It acts at the intermediary between the current application and underlying database(s).
This is responsible for mapping object requests to database requests, managing caching, transaction
consistency, locking, etc. by delegating to the correct components to handle these tasks.
EOS
);

our @CARP_NOT = qw( UR::Object::Iterator );

# These references all point to internal structures of the current process context.
# They are created here for boostrapping purposes, because they must exist before the object itself does.

our $all_objects_loaded ||= {};               # Master index of all tracked objects by class and then id.
our $all_change_subscriptions ||= {};         # Index of other properties by class, property_name, and then value.
our $all_objects_are_loaded ||= {};           # Track when a class informs us that all objects which exist are loaded.
our $all_params_loaded ||= {};                # Track parameters used to load by class then _param_key

# These items are used by prune_object_cache() to control the cache size
our $all_objects_cache_size ||= 0;            # count of the unloadable objects we've loaded from data sources
our $cache_last_prune_serial ||= 0;           # serial number the last time we pruned objects
our $cache_size_highwater;                    # high water mark for cache size.  Start pruning when $all_objects_cache_size goes over
our $cache_size_lowwater;                     # low water mark for cache size
our $GET_COUNTER = 1;                         # This is where the serial number for the __get_serial key comes from

our $object_fabricators = {};         # Maps object fabricator closures to the hashref of things they want to put into all_params_loaded
our $is_multiple_loading_iterators = 0; # A boolean flag used in the loading iterator to control whether we need to inject loaded objects into other loading iterators' cached lists
our $loading_iterators = [];          # A list of active loading iterators

# For bootstrapping.
$UR::Context::current = __PACKAGE__;

# called by UR.pm during bootstraping
my $initialized = 0;
sub _initialize_for_current_process {
    my $class = shift;
    if ($initialized) {
        die "Attempt to re-initialize the current process?";
    }

    my $root_id = $ENV{UR_CONTEXT_ROOT} ||= 'UR::Context::DefaultRoot';
    $UR::Context::root = UR::Context::Root->get($root_id);
    unless ($UR::Context::root) {
        die "Failed to find root context object '$root_id':!?  Odd value in environment variable UR_CONTEXT_ROOT?";
    }

    if (my $base_id = $ENV{UR_CONTEXT_BASE}) {
        $UR::Context::base = UR::Context::Process->get($base_id);
        unless ($UR::Context::base) {
            die "Failed to find base context object '$base_id':!?  Odd value in environment variable UR_CONTEXT_BASE?";
        }
    } 
    else {
        $UR::Context::base = $UR::Context::root;
    }

    $UR::Context::process = UR::Context::Process->_create_for_current_process(parent_id => $UR::Context::base);

    if (exists $ENV{'UR_CONTEXT_CACHE_SIZE_LOWWATER'} || exists $ENV{'UR_CONTEXT_CACHE_SIZE_HIGHWATER'}) {
        $UR::Context::destroy_should_clean_up_all_objects_loaded = 1;
        $cache_size_highwater = $ENV{'UR_CONTEXT_CACHE_SIZE_HIGHWATER'} || 0;
        $cache_size_lowwater = $ENV{'UR_CONTEXT_CACHE_SIZE_LOWWATER'} || 0;
    }


    # This changes when we initiate in-memory transactions on-top of the basic, heavier weight one for the process.
    $UR::Context::current = $UR::Context::process;

    if (exists $ENV{'UR_CONTEXT_MONITOR_QUERY'}) {
        $UR::Context::current->monitor_query($ENV{'UR_CONTEXT_MONITOR_QUERY'});
    }

    return $UR::Context::current;
}


# the current context is either the process context, or the current transaction on-top of it

*get_current = \&current;
sub current {
    return $UR::Context::current;
}

my $master_monitor_query = 0;
sub monitor_query {
    return if $UR::Object::Type::bootstrapping;
    my $self = shift;
    $self = $UR::Context::current unless (ref $self);

    if (@_) {
        if (ref $self) {
            $self->{'monitor_query'} = shift;
        } else {
            $master_monitor_query = shift;
        }

    }
    return ref($self) ? $self->{'monitor_query'} : $master_monitor_query;
}

my %_query_log_times;
sub _log_query_for_rule {
    return if $UR::Object::Type::bootstrapping;
    my $self = shift;
    my($subject_class,$rule,$message) = @_;

    my $monitor_level;
    return unless ($monitor_level = $self->monitor_query);
    return if (substr($subject_class, 0,4) eq 'UR::' and $monitor_level < 2);   # Don't log queries for internal classes

    my $elapsed_time = 0;
    if ($rule) {
        my $time_now = Time::HiRes::time();
        if (! exists $_query_log_times{$rule}) {
            $_query_log_times{$rule} = $time_now;
        } else {
            $elapsed_time = $time_now - $_query_log_times{$rule};
        }
    }

    if ($elapsed_time) {
        $message .= sprintf("  Elapsed %.4f s", $elapsed_time);
    }
    $self->status_message($message);
}

sub _log_done_elapsed_time_for_rule {
    my($self, $rule) = @_;

    delete $_query_log_times{$rule};
}


sub resolve_data_sources_for_class_meta_and_rule {
    my $self = shift;
    my $class_meta = shift;
    my $boolexpr = shift;  ## ignored in the default case    

    my $class_name = $class_meta->class_name;

    # These are some hard-coded cases for splitting up class-classes
    # and data dictionary entities into namespace-specific meta DBs.
    # Maybe there's some more generic way to move this somewhere else

    # FIXME This part is commented out for the moment.  When class info is in the 
    # Meta DBs, then try getting this to work
    #if ($class_name eq 'UR::Object::Type') {
    #    my %params = $boolexpr->legacy_params_hash;
    #    my($namespace) = ($params->{'class_name'} =~ m/^(\w+?)::/);
    #    $namespace ||= $params->{'class_name'};  # In case the class name is just the namespace
    #    
    #    return $namespace . '::DataSource::Meta';
    #}

    my $data_source;

    # For data dictionary items
    # When the FileMux datasource is more generalized and works for
    # any kind of underlying datasource, this code can move from here 
    # and into the base class for Meta datasources
    if ($class_name->isa('UR::DataSource::RDBMS::Entity')) {
        if (!defined $boolexpr) {
            $DB::single=1;
        }

        my $params = $boolexpr->legacy_params_hash;
        my $namespace;
        if ($params->{'namespace'}) {
            $namespace = $params->{'namespace'};
            $data_source = $params->{'namespace'} . '::DataSource::Meta';

        } elsif ($params->{'data_source'} &&
                 ! ref($params->{'data_source'}) &&
                 $params->{'data_source'}->can('get_namespace')) {

            $namespace = $params->{'data_source'}->get_namespace;
            $data_source = $namespace . '::DataSource::Meta';

        } elsif ($params->{'data_source'} &&
                 ref($params->{'data_source'}) eq 'ARRAY') {
            my %namespaces = map { $_->get_namespace => 1 } @{$params->{'data_source'}};
            unless (scalar(keys %namespaces) == 1) {
                Carp::confess("get() across multiple namespaces is not supported");
            }
            $namespace = $params->{'data_source'}->[0]->get_namespace;
            $data_source = $namespace . '::DataSource::Meta';
        } else {
            Carp::confess("Required parameter (namespace or data_source_id) missing");
            #$data_source = 'UR::DataSource::Meta';
        }

        if (my $exists = UR::Object::Type->get($data_source)) {
            # switch the terminology above to stop using $data_source for the class name
            # now it's the object..
            $data_source = $data_source->get();
        }
        else {
            $self->warning_message("no data source $data_source: generating for $namespace...");
            UR::DataSource::Meta->generate_for_namespace($namespace);
            $data_source = $data_source->get();
        }

        unless ($data_source) {
            Carp::confess "Failed to find or generate a data source for meta data for namespace $namespace!";
        }

    } else {
        $data_source = $class_meta->data_source;
    }

    if ($data_source) {
        $data_source = $data_source->resolve_data_sources_for_rule($boolexpr);
    }
    return $data_source;
}


# this is used to determine which data source an object should be saved-to

sub resolve_data_source_for_object {
    my $self = shift;
    my $object = shift;
    my $class_meta = $object->__meta__;
    my $class_name = $class_meta->class_name;
    
    if ($class_name->isa('UR::DataSource::RDBMS::Entity') || $class_name->isa('UR::DataSource::RDBMS::Entity::Ghost')) {
        my $data_source = $object->data_source;
        my($namespace) = ($data_source =~ m/(^\w+?)::DataSource/);
        my $ds_name = $namespace . '::DataSource::Meta';
        return $ds_name->get();
    }

    # Default behavior
    my $ds = $class_meta->data_source;
    return $ds;
}

# this turns on and off light caching (weak refs)

sub _light_cache {
    if (@_ > 1) {
        $UR::Context::light_cache = $_[1];
        $UR::Context::destroy_should_clean_up_all_objects_loaded = $UR::Context::light_cache;
    }
    return $UR::Context::light_cache;
}


# Given a rule, and a property name not mentioned in the rule,
# can we infer the value of that property from what actually is in the rule?

sub infer_property_value_from_rule {
    my($self,$wanted_property_name,$rule) = @_;

    # First, the easy case...  The property is directly mentioned in the rule
    my $value = $rule->value_for($wanted_property_name);
    if (defined $value) {
        return $value;
    }

    my $subject_class_name = $rule->subject_class_name;
    my $subject_class_meta = UR::Object::Type->get($subject_class_name);
    my $wanted_property_meta = $subject_class_meta->property_meta_for_name($wanted_property_name);
    unless ($wanted_property_meta) {
        $self->error_message("Class $subject_class_name has no property named $wanted_property_name");
        return;
    }

    if ($wanted_property_meta->is_delegated) {
        $self->context_return($self->_infer_delegated_property_from_rule($wanted_property_name,$rule));
    } else {
        $self->context_return($self->_infer_direct_property_from_rule($wanted_property_name,$rule));
    }
}

our $sig_depth = 0;
sub add_change_to_transaction_log {
    my ($self,$subject, $property, @data) = @_;

    my ($class,$id);
    if (ref($subject)) {
        $class = ref($subject);
        $id = $subject->id;
        unless ($property eq 'load' or $property eq 'define' or $property eq 'unload') {
            $subject->{_change_count}++;
            #print "changing $subject $property @data\n";    
        }
    }
    else {
        $class = $subject;
        $subject = undef;
        $id = undef;
    }

    if ($UR::Context::Transaction::log_all_changes) {
        # eventually all calls to __signal_change__ will go directly here
        UR::Context::Transaction->log_change($subject, $class, $id, $property, @data);
    }

    if (my $index_list = $UR::Object::Index::all_by_class_name_and_property_name{$class}{$property}) {
        unless ($property eq 'create' or $property eq 'load' or $property eq 'define') {
            for my $index (@$index_list) {
                $index->_remove_object(
                    $subject, 
                    { $property => $data[0] }
                ) 
            }
        }
        
        unless ($property eq 'delete' or $property eq 'unload') {
            for my $index (@$index_list) {
                $index->_add_object($subject)
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
        &$callback($subject, $property, @data)
    }
    $sig_depth--;

    return scalar(@matches);
}


sub query {
    my $self = shift;

    # Fast optimization for the default case.
    {
        no warnings;
        if (exists $UR::Context::all_objects_loaded->{$_[0]}) {
            my $is_monitor_query = $self->monitor_query;
            if (my $obj = $UR::Context::all_objects_loaded->{$_[0]}->{$_[1]}) {
                # Matched the class and ID directly - pull it right out of the cache
                if ($is_monitor_query) {
                    $self->_log_query_for_rule($_[0], undef, Carp::shortmess("QUERY: class $_[0] by ID $_[1]"));
                    $self->_log_query_for_rule($_[0], undef, "QUERY: matched 1 cached object\nQUERY: returning 1 object\n\n");
                }

                $obj->{'__get_serial'} = $UR::Context::GET_COUNTER++;
                return $obj;

            } elsif (my $subclasses = $UR::Object::_init_subclasses_loaded{$_[0]}) {
                # Check subclasses of the requested class, along with the ID
                # yes, it only goes one level deep.  This should catch enough cases to be worth it.
                # Deeper searches will be covered by get_objects_for_class_and_rule()
                foreach my $subclass (@$subclasses) {
                    if (exists $UR::Context::all_objects_loaded->{$subclass} and
                        my $obj = $UR::Context::all_objects_loaded->{$subclass}->{$_[1]}
                    ) {
                        if ($is_monitor_query) {
                            $self->_log_query_for_rule($_[0], undef, Carp::shortmess("QUERY: class $_[0] by ID $_[1]"));
                            $self->_log_query_for_rule($_[0], undef, "QUERY: matched 1 cached object in subclass $subclass\nQUERY: returning 1 object\n\n");
                        }

                        $obj->{'__get_serial'} = $UR::Context::GET_COUNTER++;
                        return $obj;
                    }
                }
            }
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
            my %params = $rule->params_list();
            $DB::single=1;
            print "Got multiple matches for class $class\nparams were: ".join(', ', map { "$_ => " . $params{$_} } keys %params) . "\nmatched objects were:\n";
            foreach my $o (@objects) {
               print "Object $o\n";
               foreach my $k ( keys %$o) {
                   print "$k => ".$o->{$k}."\n";
               }
            }
            Carp::confess("Multiple matches for $class query!". Data::Dumper::Dumper([$rule->params_list]));
            Carp::confess("Multiple matches for $class, ids: ",map {$_->id} @objects, "\nParams: ",
                           join(', ', map { "$_ => " . $params{$_} } keys %params)) if ( @objects > 1 and defined(wantarray));
        }
        
        return $objects[0];
    }

    return $UR::Context::current->get_objects_for_class_and_rule($class, $rule);
}


our $construction_method = 'create';

# Pulled out the complicated code of create_entity() below that deals with
# abstract classes and subclassify_by
sub _create_entity_from_abstract_class {
    my $self = shift;

    my $class = shift;
    my $class_meta = $class->__meta__;
    my($rule, %extra) = UR::BoolExpr->resolve_normalized($class, @_);

    # If we can easily determine the correct subclass, delegate to that subclass' create()
    my $subclassify_by = $class_meta->subclassify_by();
    unless (defined $subclassify_by) {
        Carp::croak("Can't call $construction_method on abstract class $class without a subclassify_by property");
    }

    my $sub_class_name = $rule->value_for($subclassify_by);
    unless (defined $sub_class_name) {
        # The subclassification wasn't included in the rule
        my $property_meta = $class_meta->property($subclassify_by);
        unless ($property_meta) {
            Carp::croak("Abstract class $class has subclassify_by $subclassify_by, but no property exists by that name");
        }

        # There are a few different ways the property can supply a value for subclassify_by...
        # The sure-fire way to get a value is to go ahead an instantiate the object into the
        # base/abstract class, and then we can just call the property as a method.  There's
        # a lot of overhead in that, so first we'll try some of the easier, common-case ways

        if ($property_meta->default_value) {
            # The property has a default value
            $sub_class_name = $property_meta->default_value();

        } elsif ($property_meta->is_calculated and ref($property_meta->calculate) eq 'CODE') {
            # It's calculated via a coderef

            my $calculate_from = $property_meta->calculate_from;
            my @calculate_params;
            foreach my $prop_name ( @$calculate_from ) {
                # The things in calculate_from must appear in the rule
                unless ($rule->specifies_value_for($prop_name)) {
                    Carp::croak("Class $class subclassify_by calculation property '$subclassify_by' "
                                . "requires '$prop_name' in the $construction_method() params\n"
                                . "Params were: " . UR::Util->display_string_for_params_list($rule->params_list));
                }
                push @calculate_params, $rule->value_for($prop_name);
            }

            my $sub = $property_meta->calculate;
            unless ($sub) {
                Carp::croak("Can't use undefined value as subroutine reference while resolving "
                            . "value for class $class calculated property '$subclassify_by'");
            }
            $sub_class_name = $sub->(@calculate_params);

        } elsif ($property_meta->is_calculated and !ref($property_meta->calculate)) {
            # It's calculated via a string that's eval-ed
            Carp::croak("Can't use a non-coderef as a calculation for class $class subclassify_by");

        } elsif ($property_meta->is_delegated) {
            #Carp::croak("Delegated properties are not supported for subclassifying $class with property '$subclassify_by'");
            my @values = $self->infer_property_value_from_rule($subclassify_by, $rule);
            if (! @values ) {
                Carp::croak("Invalid parameters for $class->$construction_method(): "
                            . "Couldn't infer a value for indirect property '$subclassify_by' via rule $rule");
            } elsif (@values > 1) {
                Carp::croak("Invalid parameters for $class->$construction_method(): "
                            . "Infering a value for property '$subclassify_by' via rule $rule returned multiple values: "
                            . join(', ', @values));
            } else {
                $sub_class_name = $values[0];
            }

        } else {
            Carp::croak("Can't use undefined value as a subclass name for $class property '$subclassify_by'");
        }
    }

    unless (defined $sub_class_name) {
        Carp::croak("Invalid parameters for $class->$construction_method(): "
                    . "Can't use undefined value as a subclass name for param '$subclassify_by'");
    }
    if ($sub_class_name eq $class) {
        Carp::croak("Invalid parameters for $class->$construction_method(): "
                    . "Value for $subclassify_by cannot be the same as the original class");
    }
    unless ($sub_class_name->isa($class)) {
        Carp::croak("Invalid parameters for $class->$construction_method(): "
                    . "Class $sub_class_name is not a subclass of $class");
    }
    return $sub_class_name->$construction_method(@_); 
}


sub create_entity {
    my $self = shift;

    my $class = shift;        
    my $class_meta = $class->__meta__;
    
    # The old way of automagic subclassing...
    # The class specifies that we should call a class method (sub_classification_method_name)
    # to determine the correct subclass
    if (my $method_name = $class_meta->first_sub_classification_method_name) {
        my($rule, %extra) = UR::BoolExpr->resolve_normalized($class, @_);
        my $sub_class_name = $class->$method_name(@_);
        if (defined($sub_class_name) and ($sub_class_name ne $class)) {
            # delegate to the sub-class to create the object
            #no warnings;
            unless ($sub_class_name->can($construction_method)) {
                $DB::single = 1;
                Carp::croak("Can't locate object method '$construction_method' via package '$sub_class_name' "
                            . "while resolving proper subclass for $class during $construction_method");

            }
            return $sub_class_name->$construction_method(@_);
        }
        # fall through if the class names match
    }

    if ($class_meta->is_abstract) {
        # The new way of automagic subclassing.  The class specifies a property (subclassify_by)
        # that holds/returns the correct subclass name
        return $self->_create_entity_from_abstract_class($class, @_);
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
        my @id_property_names = $class_meta->id_property_names
            or Carp::confess( # Bad should be at least one
            "No id property names for class ($class).  This should not have happened."
        );
        if ( @id_property_names == 1 ) { # only 1 - try to auto generate
            $id = $class_meta->autogenerate_new_object_id($rule);
            unless ( defined $id ) {
                $class->error_message("Failed to auto-generate an ID for single ID property class ($class)");
                return;
            }
        }
        else { # multiple
            # Try to give a useful message by getting id prop names that are not deinfed
            my @missed_names;
            for my $name ( @id_property_names ) {
                push @missed_names, $name unless $rule->specifies_value_for($name);
            }
            if ( @missed_names ) { # Ok - prob w/ class def, list the ones we missed
                $class->error_message("Attempt to $construction_method $class with multiple ids without these properties: ".join(', ', @missed_names));
                return;
            }
            else { # Bad - something is really wrong... 
                Carp::confess("Attempt to $construction_method $class failed to resolve id from underlying id properties.");
            }
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

    my @inheritance = ( $class_meta, $class_meta->ancestry_class_metas );
    for my $co ( reverse @inheritance ) {
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

            $default_values{$name} = $prop->default_value if (defined $prop->default_value);

            if ($prop->is_many) {
                $set_properties{$name} = $prop;
            }
            elsif ($prop->is_delegated || $prop->is_legacy_eav) {
                $indirect_properties{$name} = $prop;
            }
            else {
                $direct_properties{$name} = $prop;
                #delete $indirect_properties{$name};  # If this overrides a parent property
                #delete $default_values{$name};  # If this overrides a parent property
            }
            
            unless ($prop->is_mutable) {
                $immutable_properties{$name} = 1;
            }
        }
     }

    my @indirect_property_names = keys %indirect_properties;
    my @direct_property_names = keys %direct_properties;

    $params = { %$params };

    my $indirect_values = {};
    for my $property_name (keys %indirect_properties) {
        # We can get values from indirect properties either from the params
        # passed to create_entity, or from default values of those properties
        if ( exists $params->{ $property_name } ) {
            $indirect_values->{ $property_name } = delete $params->{ $property_name };
            delete $default_values{$property_name};
        } elsif (exists $default_values{$property_name}) {
            $indirect_values->{ $property_name } = delete $default_values{$property_name};
        }
    }


    # if the indirect property is immutable, but it is via something which is
    # mutable, we use those values to get or create the bridge.
    my %indirect_immutable_properties_via;
    for my $property_name (keys %$indirect_values) {
        if ($immutable_properties{$property_name}) {
            my $meta = $indirect_properties{$property_name};
            my $via = $meta->via;
            $indirect_immutable_properties_via{$via}{$property_name} = delete $indirect_values->{$property_name};
        }
    }

    for my $via (keys %indirect_immutable_properties_via) {
        my $via_property_meta = $class_meta->property_meta_for_name($via);

        my($source_indirect_property, $source_value) = each %{$indirect_immutable_properties_via{$via}};  # There'll only ever be one key/value

        unless ($via_property_meta) {
            Carp::croak("No metadata for class $class property $via while resolving indirect value for property $source_indirect_property");
        }

        my $indirect_property_meta = $class_meta->property_meta_for_name($source_indirect_property);
        unless ($indirect_property_meta) {
            Carp::croak("No metadata for class $class property $source_indirect_property while resolving indirect value for property $source_indirect_property");
        }

        unless ($indirect_property_meta->to) {
            # We're probably dealing with a subclassify_by property where the subclass has
            # implicitly overridden the indirect property in the parent class with a constant-value
            # property in the subclass.  Try asking the parent class about a property of the same name
            ($indirect_property_meta) = grep { $_->property_name eq $indirect_property_meta->property_name } $class_meta->ancestry_property_metas();
            unless ($indirect_property_meta and $indirect_property_meta->to) {
                Carp::croak("Can't resolve indirect relationship for possibly overridden property '$source_indirect_property'"
                            . " in class $class.  Parent classes have no property named '$source_indirect_property'");
            }
        }
        my $foreign_class = $via_property_meta->data_type;
        my $foreign_property = $indirect_property_meta->to;
        my $foreign_object = $foreign_class->get($foreign_property => $source_value);
        unless ($foreign_object) {
            # This will trigger recursion back here (into create_entity() ) if this property is multiply
            # indirect, such as through a bridge object
            $foreign_object = $foreign_class->create($foreign_property => $source_value);
            unless ($foreign_object) {
                Carp::croak("Can't create object of class $foreign_class with params ($foreign_property => '$source_value')"
                            . " while resolving indirect value for class $class property $source_indirect_property");
            }

        }

        my @joins = $indirect_property_meta->_get_joins();
        my %local_properties_to_set;
        foreach my $join ( @joins ) {
            for (my $i = 0; $i < @{$join->{'source_property_names'}}; $i++) {
                my $source_property_name = $join->{'source_property_names'}->[$i];
                next unless (exists $direct_properties{$source_property_name});
                my $foreign_property_name = $join->{'foreign_property_names'}->[$i];
                my $value = $foreign_object->$foreign_property_name;

                if ($rule->specifies_value_for($source_property_name)
                        and
                        $rule->value_for($source_property_name) ne $value)
                {
                    Carp::croak("Invalid parameters for $class->$construction_method(): "
                                . "Conflicting values for property '$source_property_name'.  $construction_method rule "
                                . "specifies value '" . $rule->value_for($source_property_name) . "' but "
                                . "indirect immutable property '$source_indirect_property' with value "
                                . "$source_value requires it to be '$value'");
                }

                $local_properties_to_set{$source_property_name} = $value;
            }
        }
        # transfer the values we resolved back into %$params
        my @param_keys = keys %local_properties_to_set;
        @$params{@param_keys} = @local_properties_to_set{@param_keys};
    }

    my $set_values = {};
    for my $property_name (keys %set_properties) {
        $set_values->{ $property_name } =
            delete $params->{ $property_name }
                if ( exists $params->{ $property_name } );
    }

    # create the object.
    my $entity = $class->_create_object(%default_values, %$params, @extra, id => $id);
    return unless $entity;
    #if ($class_meta->is_abstract) {
    #    # The new way of automagic subclassing with the class meta's subclassify_by property
    #    #return $self->_subclassify_entity_of_abstract_class($entity, %extra, %default_values, %$params, @extra, id => $id);
    #    return $self->_subclassify_entity_of_abstract_class($entity, %extra, %default_values, %$params, @extra, id => $id, @_);
    #    # FIXME - don't forget to remove the object cache entry that was created for the parent class obj
    #}


    # If a property is calculated + immutable, and it wasn't supplied in the params,
    # that means we need to run the calculation once and store the value in the
    # object as a read-only attribute
    foreach my $property_name ( keys %immutable_properties )  {
        my $property_meta = $property_objects{$property_name};
        if (!exists($params->{$property_name}) and $property_meta and $property_meta->is_calculated) {
            # If we call the regular accessor here, it'll go into the read-only
            # accessor closure.  Instead, we need to look up the 'calculate'
            # meta-property
            #my $sub = $property_meta->calculate;
            #unless ($sub) {
            #    Carp::croak("Can't use an undefined value as subroutine reference while resolving value for class $class property '$property_name'");
            #}
            #my $value = eval { $sub->($entity) };
            my $value = $entity->$property_name;
            #if ($@) {
            #    Carp::croak("Can't resolve value for class $class property '$property_name': $@");
            #}
            $params->{$property_name} = $value;
        }
     }

     foreach my $co ( @inheritance ) {
        # If this class inherits from something with subclassify_by, make sure the param
        # actually matches.  If it's not supplied, then set it to the same as the class create()
        # is being called on
        if ( $class ne $co->class_name
                 and $co->is_abstract
                 and my $subclassify_by = $co->subclassify_by
           ) {
            my $param_value = $rule->value_for($subclassify_by);
            $param_value = eval { $entity->$subclassify_by } unless (defined $param_value);
            $param_value = $default_values{$subclassify_by} unless (defined $param_value);
            if (! defined $param_value) {
                # This should have been taken care of by the time we got here...
                Carp::croak("Invalid parameters for $class->$construction_method(): " .
                            "Can't use an undefined value as a subclass name for param '$subclassify_by'");

            } elsif ($param_value ne $class) {
                Carp::croak("Invalid parameters for $class->$construction_method(): " .
                            "Value for subclassifying param '$subclassify_by' " .
                            "($param_value) does not match the class it was called on ($class)");
            }
        }
    }

    # add items for any multi properties
    if (%$set_values) {
        for my $property_name (keys %$set_values) {
            my $meta = $set_properties{$property_name};
            my $singular_name = $meta->singular_name;
            my $adder = 'add_' . $singular_name;
            my $value = $set_values->{$property_name};
            unless (ref($value) eq 'ARRAY') {
                die "odd non-array refrence used for 'has-many' property $property_name for $class: $value!";
            }
            for my $item (@$value) {
                if (ref($item) eq 'ARRAY') {
                    $entity->$adder(@$item);
                }
                elsif (ref($item) eq 'HASH') {
                    $entity->$adder(%$item);
                }
                else {
                    $entity->$adder($item);
                }
            }
        }
    }    

    # set any indirect mutable properties
    if (%$indirect_values) {
        for my $property_name (keys %$indirect_values) {
            $entity->$property_name($indirect_values->{$property_name});
        }
    }

    if (%immutable_properties) {
        my @problems = $entity->__errors__();
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
                my $msg = 'Failed to $construction_method ' . $class . ' with invalid immutable properties:'
                    . join("\n", @errors_fatal_to_construction);
                #$entity->_delete_object;
                #die $msg;
            }
        }
    }
    
    $entity->__signal_change__($construction_method);
    $entity->__signal_change__('load') if $construction_method eq '__define__';
    $entity->{'__get_serial'} = $UR::Context::GET_COUNTER++;
    $UR::Context::all_objects_cache_size++;
    return $entity;
}



sub delete_entity {
    my ($self,$entity) = @_;

    if (ref($entity)) {
        # Delete the specified object.
        if ($entity->{db_committed} || $entity->{db_saved_uncommitted}) {

            # gather params for the ghost object
            my $do_data_source;
            my %ghost_params;
            #my @pn;
            #{ no warnings 'syntax';
            #   @pn = grep { $_ ne 'data_source_id' || ($do_data_source=1 and 0) } # yes this really is '=' and not '=='
            #         grep { exists $entity->{$_} }
            #         $entity->__meta__->all_property_names;
            #}
            my(@prop_names, @many_prop_names);
            foreach my $prop_name ( $entity->__meta__->all_property_names) {
                next unless exists $entity->{$prop_name};  # skip non-directly-stored properties
                if ($prop_name eq 'data_source_id') {
                    $do_data_source = 1;
                    next;
                }
                if (ref($entity->{$prop_name}) eq 'ARRAY') {
                    push @many_prop_names, $prop_name;
                } else {
                    push @prop_names, $prop_name;
                }
            }
 
            
            # we're not really allowed to interrogate the data_source property directly
            @ghost_params{@prop_names} = $entity->get(@prop_names);  # hrm doesn't work for is_many properties :(
            foreach my $prop_name ( @many_prop_names ) {
                my @values = $entity->get($prop_name);
                $ghost_params{$prop_name} = \@values;
            }
            if ($do_data_source) {
                $ghost_params{'data_source_id'} = $entity->{'data_source_id'};
            }    

            # create ghost object
            my $ghost = $entity->ghost_class->_create_object(id => $entity->id, %ghost_params);
            unless ($ghost) {
                $DB::single = 1;
                Carp::confess("Failed to constructe a deletion record for an unsync'd delete.");
            }
            $ghost->__signal_change__("create");

            for my $com (qw(db_committed db_saved_uncommitted)) {
                $ghost->{$com} = $entity->{$com}
                    if $entity->{$com};
            }

        }
        $entity->__signal_change__('delete');
        $entity->_delete_object;
        return $entity;
    }
    else {
        Carp::confess("Can't call delete as a class method.");
    }
}

# This one works when the rule specifies the value of an indirect property, and we want
# the value of a direct property of the class
sub _infer_direct_property_from_rule {
    my($self,$wanted_property_name,$rule) = @_;

    my $rule_template = $rule->template;
    my @properties_in_rule = $rule_template->_property_names; # FIXME - why is this method private?
    my $subject_class_name = $rule->subject_class_name;
    my $subject_class_meta = UR::Object::Type->get($subject_class_name);


    my($alternate_class,$alternate_get_property, $alternate_wanted_property);

    my @r_values; # There may be multiple properties in the rule that will get to the wanted property
    PROPERTY_IN_RULE:
    foreach my $property_name ( @properties_in_rule) {
        my $property_meta = $subject_class_meta->property_meta_for_name($property_name);
        if ($property_meta->is_delegated) {

            my $linking_property_meta = $subject_class_meta->property_meta_for_name($property_meta->via);
            my($reference,$ref_name_getter, $ref_r_name_getter);
            if ($linking_property_meta->reverse_as) {
                eval{ $linking_property_meta->data_type->class() };  # Load the class if it isn't already loaded
                $reference = UR::Object::Reference->get(class_name => $linking_property_meta->data_type,
                                                        delegation_name => $linking_property_meta->reverse_as);
                $ref_name_getter = 'r_property_name';
                $ref_r_name_getter = 'property_name';
                $alternate_class = $reference->class_name;
            } else {
                $reference = UR::Object::Reference->get(class_name => $linking_property_meta->class_name,
                                                        delegation_name => $linking_property_meta->property_name);
                $ref_name_getter = 'property_name';
                $ref_r_name_getter = 'r_property_name';
                $alternate_class = $reference->r_class_name;
            }

            my @ref_properties = $reference->get_property_links;
            foreach my $ref_property ( @ref_properties ) {
                my $ref_property_name = $ref_property->$ref_name_getter;
                if ($ref_property_name eq $wanted_property_name) {
                    $alternate_wanted_property = $ref_property->$ref_r_name_getter;
                }
            }
            $alternate_get_property = $property_meta->to;
            #next PROPERTY_IN_RULE unless $alternate_wanted_property;
        }

        unless ($alternate_wanted_property) {
            # Either this was also a direct property of the rule, or there's no
            # obvious link between the indirect property and the wanted property.
            # the caller probably just should have done a get()
            $alternate_wanted_property = $wanted_property_name;
            $alternate_get_property = $property_name;
            $alternate_class = $subject_class_name;
        }
     
        my $value_from_rule = $rule->value_for($property_name);
        my @alternate_values;
        eval {
            # Inside an eval in case the get() throws an exception, the next 
            # property in the rule may succeed
            my @alternate_objects = $self->query($alternate_class, $alternate_get_property  => $value_from_rule );
            @alternate_values = map { $_->$alternate_wanted_property } @alternate_objects;
        };
        next unless (@alternate_values);

        push @r_values, \@alternate_values;
    }

    if (@r_values == 0) {
        # no solutions found
        return;

    } elsif (@r_values == 1) {
        # there was only one solution
        return @{$r_values[0]};

    } else {
        # multiple solutions.  Only return the intersection of them all
        # FIXME - this totally won't work for properties that return objects, listrefs or hashrefs
        # FIXME - this only works for AND rules - for now, that's all that exist
        my %intersection = map { $_ => 1 } @{ shift @r_values };
        foreach my $list ( @r_values ) {
            %intersection = map { $_ => 1 } grep { $intersection{$_} } @$list;
        }
        return keys %intersection;
    }
}


# we want the value of a delegated property, and the rule specifies
# a direct value
sub _infer_delegated_property_from_rule {
    my($self, $wanted_property_name, $rule) = @_;

    my $rule_template = $rule->template;
    my $subject_class_name = $rule->subject_class_name;
    my $subject_class_meta = UR::Object::Type->get($subject_class_name);

    my $wanted_property_meta = $subject_class_meta->property_meta_for_name($wanted_property_name);
    unless ($wanted_property_meta->via) {
        Carp::croak("There is no linking meta-property (via) on property $wanted_property_name on $subject_class_name");
    }

    my $linking_property_meta = $subject_class_meta->property_meta_for_name($wanted_property_meta->via);
    my $alternate_wanted_property = $wanted_property_meta->to;

    my($reference,$ref_name_getter,$ref_r_name_getter,$alternate_class);
    if ($linking_property_meta->reverse_as) {
        eval{ $linking_property_meta->data_type->class() };  # Load the class if it isn't already loaded
        $reference = UR::Object::Reference->get(class_name => $linking_property_meta->data_type,
                                                delegation_name => $linking_property_meta->reverse_as);
        $ref_name_getter = 'r_property_name';
        $ref_r_name_getter = 'property_name';
        $alternate_class = $reference->class_name;
    } else {
        $reference = UR::Object::Reference->get(class_name => $linking_property_meta->class_name,
                                                delegation_name => $linking_property_meta->property_name);
        $ref_name_getter = 'property_name';
        $ref_r_name_getter = 'r_property_name';
        $alternate_class = $reference->r_class_name;
    }

    my %alternate_get_params;
    my @ref_properties = $reference->get_property_links;
    foreach my $ref_property ( @ref_properties ) {
        my $ref_property_name = $ref_property->$ref_name_getter;
        if ($rule_template->specifies_value_for($ref_property_name)) {
            my $value = $rule->value_for($ref_property_name);
            $alternate_get_params { $ref_property->$ref_r_name_getter } = $value;
        }
    }
        
    my @alternate_values;
    eval {
        my @alternate_objects = $self->query($alternate_class, %alternate_get_params);
        @alternate_values = map { $_->$alternate_wanted_property } @alternate_objects;
    };
    return @alternate_values;
}


sub object_cache_size_highwater {
    my $self = shift;

    if (@_) {
        my $value = shift;
        $cache_size_highwater = $value;

        if (defined $value) {
            if ($cache_size_lowwater and $value <= $cache_size_lowwater) {
                Carp::confess("Can't set the highwater mark less than or equal to the lowwater mark");
                return;
            }
            $UR::Context::destroy_should_clean_up_all_objects_loaded = 1;
            $self->prune_object_cache();
        } else {
            # turn it off
            $UR::Context::destroy_should_clean_up_all_objects_loaded = 0;
        }
    }
    return $cache_size_highwater;
}

sub object_cache_size_lowwater {
    my $self = shift;
    if (@_) {
        my $value = shift;
        $cache_size_lowwater = $value;

        if ($cache_size_highwater and $value >= $cache_size_highwater) {
            Carp::confess("Can't set the lowwater mark greater than or equal to the highwater mark");
            return;
        }
    }
    return $cache_size_lowwater;
}



our $is_pruning = 0;
sub prune_object_cache {
    my $self = shift;

    return if ($is_pruning);  # Don't recurse into here

    #$DB::single=1;
    return unless ($all_objects_cache_size > $cache_size_highwater);

    $is_pruning = 1;
    #$main::did_prune=1;
    my $t1;
    if ($ENV{'UR_DEBUG_OBJECT_RELEASE'}) {
        $t1 = Time::HiRes::time();
        print STDERR "MEM PRUNE begin at $t1 ",scalar(localtime($t1)),"\n";
    }
        

    my $index_id_sep = UR::Object::Index->__meta__->composite_id_separator() || "\t";

    my %classes_to_prune;
    my %data_source_for_class;
    foreach my $class ( keys %$UR::Context::all_objects_loaded ) {
        next if (substr($class,0,-6) eq '::Type'); # skip class objects

        next unless exists $UR::Context::all_objects_loaded->{$class . '::Type'};
        my $class_meta = $UR::Context::all_objects_loaded->{$class . '::Type'}->{$class};
        next unless $class_meta;
        next unless ($class_meta->is_uncachable());
        $data_source_for_class{$class} = $class_meta->data_source_id;
        #next unless $class_meta->{'data_source_id'};  # Can't unload objects with no data source
        $classes_to_prune{$class} = 1;
    }

    # NOTE: This pokes right into the object cache and futzes with Index IDs directly.
    # We can't get the Index objects though get() because we'd recurse right back into here
    my %indexes_by_class;
    foreach my $idx_id ( keys %{$UR::Context::all_objects_loaded->{'UR::Object::Index'}} ) {
        my $class = substr($idx_id, 0, index($idx_id, $index_id_sep));
        next unless $classes_to_prune{$class};
        push @{$indexes_by_class{$class}}, $UR::Context::all_objects_loaded->{'UR::Object::Index'}->{$idx_id};
    }

    my $deleted_count = 0;
    my $pass = 0;

    # Make a guess about that the target serial number should be
    # This one goes 10% between the last time we pruned, and the last get serial
    # and increases by another 10% each attempt
    #my $target_serial_increment = int(($GET_COUNTER - $cache_last_prune_serial) * $cache_size_lowwater / $cache_size_highwater );
    my $target_serial_increment = int(($GET_COUNTER - $cache_last_prune_serial) * 0.1);
    $target_serial_increment = 1 if ($target_serial_increment < 1);
    my $target_serial = $cache_last_prune_serial;
    CACHE_IS_TOO_BIG:
    while ($all_objects_cache_size > $cache_size_lowwater) {
        $pass++;

        $target_serial += $target_serial_increment;
        last if ($target_serial > $GET_COUNTER);

        foreach my $class (keys %classes_to_prune) {
            my $objects_for_class = $UR::Context::all_objects_loaded->{$class};
            $indexes_by_class{$class} ||= [];
            
            foreach my $id ( keys ( %$objects_for_class ) ) {
                my $obj = $objects_for_class->{$id};

                # Objects marked __strengthen__ed are never purged
                next if exists $obj->{'__strengthened'};

                # classes with data sources get their objects pruned immediately if
                # they're marked weakened, or at the usual time (serial is under the
                # target) if not
                # Classes without data sources get instances purged if the serial
                # number is under the target _and_ they're marked weakened
                if (
                     ( $data_source_for_class{$class} and exists $obj->{'__weakened'} )
                     or
                     ( exists $obj->{'__get_serial'}
                       and $obj->{'__get_serial'} <= $target_serial
                       and ($data_source_for_class{$class} or exists $obj->{'__weakened'})
                       and ! $obj->__changes__
                     )
                   )
                {
                    foreach my $index ( @{$indexes_by_class{$class}} ) {
                        $index->weaken_reference_for_object($obj);
                    }
                    if ($ENV{'UR_DEBUG_OBJECT_RELEASE'}) {
                        print STDERR "MEM PRUNE object $obj class $class id $id\n";
                    }

                    delete $obj->{'__get_serial'};
                    Scalar::Util::weaken($objects_for_class->{$id});
                    
                    $all_objects_cache_size--;
                    $deleted_count++;
                }
            }
        }
    }
    $is_pruning = 0;

    $cache_last_prune_serial = $target_serial;
    if ($ENV{'UR_DEBUG_OBJECT_RELEASE'}) {
        my $t2 = Time::HiRes::time();
        printf("MEM PRUNE complete, $deleted_count objects marked after $pass passes in %.4f sec\n\n\n",$t2-$t1);
    }
    if ($all_objects_cache_size > $cache_size_lowwater) {
        #$DB::single=1;
        warn "After several passes of pruning the object cache, there are still $all_objects_cache_size objects";
    }
}

   
# this is the underlying method for get/load/is_loaded in ::Object

sub get_objects_for_class_and_rule {
    my ($self, $class, $rule, $load, $return_closure) = @_;
    #my @params = $rule->params_list;
    #print "GET: $class @params\n";

    if ($cache_size_highwater
        and
        $all_objects_cache_size > $cache_size_highwater)
    {

        $self->prune_object_cache();
    }
    
    # an identifier for all objects gotten in this request will be set/updated on each of them for pruning later
    my $this_get_serial = $GET_COUNTER++;
    
    my $meta = $class->__meta__();    

    # A query on a subclass where the parent class is_abstract and has a subclassify_by property
    # (meaning that the parent class has a property which directly stores the proper subclass for
    # each row - subclasses inherit the property from the parent, and the subclass isn't is_abstract)
    # should have a filter added to the rule to keep only rows of the subclass we're interested in.
    # This will improve the SQL performance when it's later constructed.
    my $subclassify_by = $meta->subclassify_by;
    if ($subclassify_by and ! $meta->is_abstract and ! $rule->specifies_value_for($subclassify_by)) {
        $rule = $rule->add_filter($subclassify_by => $class);
    }

    # If $load is undefined, and there is no underlying context, we define it to FALSE explicitly
    # TODO: instead of checking for a data source, skip this
    # We'll always go to the underlying context, even if it has nothing. 
    # This optimization only works by coincidence since we don't stack contexts currently beyond 1.
    my $ds;
    if (!defined($load) or $load) {
        ($ds) = $self->resolve_data_sources_for_class_meta_and_rule($meta,$rule);
        if (! $ds or $class =~ m/::Ghost$/) {
            # Classes without data sources and Ghosts can only ever come from the cache
            $load = 0;  
        } 
    }
 
    # this is an arrayref of all of the cached data
    # it is set in one of two places below
    my $cached;
    
    # this is a no-op if the rule is already normalized
    my $normalized_rule = $rule->normalize;
    
    # see if we need to load if load was not defined
    unless (defined $load) {
        # check to see if the cache is complete
        # also returns a list of the complete cached objects where that list is found as a side-effect
        my ($cache_is_complete, $cached) = $self->_cache_is_complete_for_class_and_normalized_rule($class, $normalized_rule);
        $load = ($cache_is_complete ? 0 : 1);
    }

    my $is_monitor_query = $self->monitor_query;
    $self->_log_query_for_rule($class,$normalized_rule,Carp::shortmess("QUERY: Query start for rule $normalized_rule")) if ($is_monitor_query);

    # optimization for the common case
    if (!$load and !$return_closure) {
        my @c = $self->_get_objects_for_class_and_rule_from_cache($class,$normalized_rule);
        my $obj_count = scalar(@c);
        foreach ( @c ) {
            unless (exists $_->{'__get_serial'}) {
                # This is a weakened reference.  Convert it back to a regular ref
                my $class = ref $_;
                my $id = $_->id;
                my $ref = $UR::Context::all_objects_loaded->{$class}->{$id};
                $UR::Context::all_objects_loaded->{$class}->{$id} = $ref;
            }
            $_->{'__get_serial'} = $this_get_serial;
        }

        if ($is_monitor_query) {
            $self->_log_query_for_rule($class,$normalized_rule,"QUERY: matched $obj_count cached objects (no loading)");
            $self->_log_query_for_rule($class,$normalized_rule,"QUERY: Query complete after returning $obj_count object(s) for rule $rule");
            $self->_log_done_elapsed_time_for_rule($normalized_rule);
        }

        return @c if wantarray;           # array context
        return unless defined wantarray;  # null context
        Carp::confess("multiple objects found for a call in scalar context!  Using " . __PACKAGE__) if @c > 1;
        return $c[0];                     # scalar context
    }

    my $normalized_rule_template = $normalized_rule->template;
    my $object_sorter = $normalized_rule_template->sorter();

    # the above process might have found all of the cached data required as a side-effect in which case
    # we have a value for this early 
    # either way: ensure the cached data is known and sorted
    if ($cached) {
        @$cached = sort $object_sorter @$cached;
    }
    else {
        $cached = [ sort $object_sorter $self->_get_objects_for_class_and_rule_from_cache($class,$normalized_rule) ];
    }
    $self->_log_query_for_rule($class, $normalized_rule, "QUERY: matched ".scalar(@$cached)." cached objects") if ($is_monitor_query);
    foreach ( @$cached ) {
        unless (exists $_->{'__get_serial'}) {
            # This is a weakened reference.  Convert it back to a regular ref
            my $class = ref $_;
            my $id = $_->id;
            my $ref = $UR::Context::all_objects_loaded->{$class}->{$id};
            $UR::Context::all_objects_loaded->{$class}->{$id} = $ref;
        }
        $_->{'__get_serial'} = $this_get_serial;
    }

    
    # make a loading iterator if loading must be done for this rule
    my $loading_iterator;
    if ($load) {
        # this returns objects from the underlying context after importing them into the current context,
        # but only if they did not exist in the current context already
        $self->_log_query_for_rule($class, $normalized_rule, "QUERY: importing from underlying context with rule $normalized_rule") if ($is_monitor_query);
        my $underlying_context_iterator = $self->_create_import_iterator_for_underlying_context($normalized_rule, $ds, $this_get_serial);

        # Some thoughts about the loading iterator's behavior around changing objects....
        #
        # The system attempts to return objects matching the rule at the time the iterator is
        # created, even if they change between the time it's created and when next() returns 
        # them.  There is a problem if the object in question is actually deleted (ie. isa
        # UR::DeletedRef).  Since DeletedRef's die any time you try to use them, the object
        # sorters can't sort them.  Instead, we'll just punt and throw an exception ourselves
        # if we come across one.
        # 
        # This seems like the least suprising thing to do, but there are other solutions:
        # 1) just plain don't return the deleted object
        # 2) use signal_change to register a callback which will remove objects being deleted
        #    from all the in-process iterator @$cached lists (accomplishes the same as #1).
        #    For completeness, this may imply that other signal_change callbacks would remove
        #    objects that no longer match rules for in-process iterators, and that means that 
        #    next() returns things true at the time next() is called, not when the iterator
        #    is created.
        # 3) Put in some additional infrastructure so we can pull out the ID of a deleted
        #    object.  That lets us call $next_object->id at the end of the closure, and return these
        #    deleted objects back to the user.  Problem being that the user then can't really
        #    do anything with them.  But it would be consistent about returning _all_ objects
        #    that matched the rule at iterator creation time
        # 4) Like #3, but just always return the deleted object before any underlying_context
        #    object, and then don't try to get its ID at the end if the iterator if it's deleted
 
        # These are captured by the closure...
        my($last_loaded_id, $next_obj_current_context, $next_obj_underlying_context,$underlying_context_objects_count,$cached_objects_count);
        my $me_loading_iterator_as_string;  # See note below the closure definition

        $underlying_context_objects_count = 0;
        $cached_objects_count = 0;
        # this will interleave the above with any data already present in the current context
        $loading_iterator = sub {
            PICK_NEXT_OBJECT_FOR_LOADING:
            if ($underlying_context_iterator && ! $next_obj_underlying_context) {
                ($next_obj_underlying_context) = $underlying_context_iterator->(1);
 
                if ($is_monitor_query and $next_obj_underlying_context) {
                    $self->_log_query_for_rule($class, $normalized_rule, "QUERY: loading 1 object from underlying context") if ($return_closure);
                    $underlying_context_objects_count++;
                }
                # See if this newly loaded object needs to be inserted into any of the other
                # loading iterators' cached list.  We only need to check this is there is more
                # than one iterator running....
                if ($next_obj_underlying_context and $UR::Context::is_multiple_loading_iterators) {
                    $self->_inject_object_into_other_loading_iterators($next_obj_underlying_context, $me_loading_iterator_as_string);
                }
            }

            unless ($next_obj_current_context) {
                ($next_obj_current_context) = shift @$cached;
                $cached_objects_count++ if ($is_monitor_query and $next_obj_current_context);
            }

            if ($next_obj_current_context and $next_obj_current_context->isa('UR::DeletedRef')) {
                 my $obj_to_complain_about = $next_obj_current_context;
                 # undef it in case the user traps the exception, next time we'll pull another off the list
                 $next_obj_current_context = undef;
                 Carp::croak("Attempt to fetch an object which matched $rule when the iterator was created, but was deleted in the meantime:\n"
                             . Data::Dumper::Dumper($obj_to_complain_about) );
             }


            # We're turning off warnings to avoid complaining in the elsif()
            no warnings 'uninitialized';
            if (!$next_obj_underlying_context) {
                if ($is_monitor_query) {
                    $self->_log_query_for_rule($class, $normalized_rule, "QUERY: loaded $underlying_context_objects_count object(s) total from underlying context.");
                }
                $underlying_context_iterator = undef;

            } elsif ($last_loaded_id eq $next_obj_underlying_context->id) {
                # during a get() with -hints or is_many+is_optional (ie. something with an
                # outer join), it's possible that the join can produce the same main object
                # as it's chewing through the (possibly) multiple objects joined to it.
                # Since the objects will be returned sorted by their IDs, we only have to
                # remember the last one we saw
                # FIXME - is this still true now that the underlying context iterator will
                # never return objects that already exist in the cache?
                $next_obj_underlying_context = undef;
                goto PICK_NEXT_OBJECT_FOR_LOADING;
            }
            use warnings 'uninitialized';
            
            # decide which pending object to return next
            # both the cached list and the list from the database are sorted separately,
            # we're merging these into one return stream here
            my $comparison_result;
            if ($next_obj_underlying_context && $next_obj_current_context) {
                $comparison_result = $object_sorter->($next_obj_underlying_context, $next_obj_current_context);
            }
            
            my $next_object;
            if (
                $next_obj_underlying_context 
                and $next_obj_current_context 
                and $comparison_result == 0 # $next_obj_underlying_context->id eq $next_obj_current_context->id
            ) {
                # the database and the cache have the same object "next"
                $self->_log_query_for_rule($class, $normalized_rule, "QUERY: loaded object was already cached") if ($is_monitor_query);
                $next_object = $next_obj_current_context;
                $next_obj_current_context = undef;
                $next_obj_underlying_context = undef;
            }
            elsif (                
                $next_obj_underlying_context
                and (
                    (!$next_obj_current_context)
                    or
                    ($comparison_result < 0) # ($next_obj_underlying_context->id le $next_obj_current_context->id) 
                )
            ) {
                # db object is next to be returned
                $next_object = $next_obj_underlying_context;
                $next_obj_underlying_context = undef;
            }
            elsif (                
                $next_obj_current_context 
                and (
                    (!$next_obj_underlying_context)
                    or 
                    ($comparison_result > 0) # ($next_obj_underlying_context->id ge $next_obj_current_context->id) 
                )
            ) {
                # cached object is next to be returned
                $next_object = $next_obj_current_context;
                $next_obj_current_context = undef;
            }

            return unless defined $next_object;

            $last_loaded_id = $next_object->id;

            return $next_object;
        };

        bless $loading_iterator, 'UR::Context::loading_iterator_tracker';
        Sub::Name::subname('UR::Context::__loading_iterator(closure)__',$loading_iterator);

        # Inside the closure, it needs to know its own address, but without holding a real reference
        # to itself - otherwise the closure would never go out of scope, the destructor would never
        # get called, and the list of outstanding loaders would never get pruned.  This way, the closure
        # holds a reference to the string version of its address, which is the only thing it really
        # needed anyway
        $me_loading_iterator_as_string = $loading_iterator . '';

        # Add ourselves to the list of outstanding loading iterators.  The underlying
        # context iterator will need to know these
        push @$UR::Context::loading_iterators, [ $loading_iterator . '',  # force to a string so the list doesn't hold a real ref
                                                 $rule,
                                                 $object_sorter,
                                                 $cached,
                                                 \$underlying_context_objects_count,
                                                 \$cached_objects_count
                                               ];
        $UR::Context::is_multiple_loading_iterators = 1 if (@$UR::Context::loading_iterators > 1);
    }
    
    if ($return_closure) {
        if ($load) {
            # return the iterator made above
            return $loading_iterator;
        }
        else {
            # make a quick iterator for the cached data
            return sub { return shift @$cached };
        }
    }
    else {
        my @results;
        if ($loading_iterator) {
            # use the iterator made above
            my $found;
            while ($found = $loading_iterator->(1)) {        
                push @results, $found;
            }
        }
        else {
            # just get the cached data
            @results = @$cached;
        }
        return unless defined wantarray;
        return @results if wantarray;
        if (@results > 1) {
            Carp::confess sprintf("Multiple results unexpected for query.\n\tClass %s\n\trule params: %s\n\tGot %d results:\n%s\n",
                        $rule->subject_class_name,
                        join(',', $rule->params_list),
                        scalar(@results),
                        Data::Dumper::Dumper(\@results));
        }
        return $results[0];
    }
}

sub UR::Context::loading_iterator_tracker::DESTROY {
    # Items in the listref are: $loading_iterator_string, $rule, $object_sorter, $cached, \$underlying_context_objects_count, \$cached_objects_count

    my $count = scalar(@$UR::Context::loading_iterators);
    for (my $i = 0; $i < $count; $i++) {
        if ($_[0] eq $UR::Context::loading_iterators->[$i]->[0]) {
            # That's me!
            if ($UR::Context::current->monitor_query) {
                my $me_iter = $UR::Context::loading_iterators->[$i];
                my $rule = $me_iter->[1];
                my $count = ${$me_iter->[4]} + ${$me_iter->[5]};
                $UR::Context::current->_log_query_for_rule($rule->subject_class_name, $rule, "QUERY: Query complete after returning $count object(s) for rule $rule.");
                $UR::Context::current->_log_done_elapsed_time_for_rule($rule);
            }

            splice(@$UR::Context::loading_iterators, $i, 1);
            $UR::Context::is_multiple_loading_iterators = 0 if ($count == 2);  # If count was 2 at the top, and we removed one, it's now 1 and it's not multiple
            return;
        }
    }
    Carp::carp('A loading iterator went out of scope, but could not be found in the loading_iterators list!?');
}

# Used by the object fabricator to inject a newly loaded object into another
# loading iterator's @$cached list.  This is to handle the case where the user creates
# an iterator which will load objects from the DB.  Before all the data from that
# iterator is read, another get() or iterator is created that covers (some of) the same
# objects which get pulled into the object cache, and the second request is run to
# completion.  Since the underlying context iterator has been changed to never return
# objects currently cached, the first iterator would have incorrectly skipped ome objects that
# were not loaded when the first iterator was created, but later got loaded by the second.
sub _inject_object_into_other_loading_iterators {
    my($self, $new_object, $iterator_to_skip) = @_;

    my $iterator_count = @$UR::Context::loading_iterators;
    ITERATOR:
    for (my $i = 0; $i < $iterator_count; $i++) {
        my($loading_iterator, $rule, $object_sorter, $cached)
                                = @{$UR::Context::loading_iterators->[$i]};
        next if ($loading_iterator eq $iterator_to_skip);  # That's me!  Don't insert into our own @$cached this way
        if ($rule->evaluate($new_object)) {

            my $cached_list_len = @$cached;
            for(my $i = 0; $i < $cached_list_len; $i++) {
                my $cached_object = $cached->[$i];
                next if $cached_object->isa('UR::DeletedRef');

                my $comparison = $object_sorter->($new_object, $cached_object);
        
                if ($comparison < 0) {
                    # The new object sorts sooner than this one.  Insert it into the list
                    splice(@$cached, $i, 0, $new_object);
                    next ITERATOR;
                } elsif ($comparison == 0) {
                    # This object is already in the list
                    next ITERATOR;
                }
            }

            # It must go at the end...
            push @$cached, $new_object;
        }
    } # end for()           
}
    


# A wrapper around the method of the same name in UR::DataSource::* to iterate over the
# possible data sources involved in a query.  The easy case (a query against a single data source)
# will return the $primary_template data structure.  If the query involves more than one data source,
# then this method also returns a list containing triples (@addl_loading_info) where each member is:
# 1) The secondary data source name
# 2) a listref of delegated properties joining the primary class to the secondary class
# 3) a rule template applicable against the secondary data source
sub _get_template_data_for_loading {
    my($self,$primary_data_source,$rule_template) = @_;

    my $primary_template = $primary_data_source->_get_template_data_for_loading($rule_template);

    unless ($primary_template->{'joins_across_data_sources'}) {
        # Common, easy case
        return $primary_template;
    }

    my @addl_loading_info;
    foreach my $secondary_data_source_id ( keys %{$primary_template->{'joins_across_data_sources'}} ) {
        my $this_ds_delegations = $primary_template->{'joins_across_data_sources'}->{$secondary_data_source_id};

        my %seen_properties;
        foreach my $delegated_property ( @$this_ds_delegations ) {
            my $delegated_property_name = $delegated_property->property_name;
            next if ($seen_properties{$delegated_property_name});

            my $operator = $rule_template->operator_for($delegated_property_name);
            $operator ||= '=';  # FIXME - shouldn't the template return this for us?
            my @secondary_params = ($delegated_property->to . ' ' . $operator);

            my $class_meta = UR::Object::Type->get($delegated_property->class_name);
            my $relation_property = $class_meta->property_meta_for_name($delegated_property->via);
     
            my $secondary_class = $relation_property->data_type;

            # we can also add in any properties in the property's joins that also appear in the rule

            my $reference = UR::Object::Reference->get(class_name => $delegated_property->class_name,
                                                       delegation_name => $delegated_property->via);
            my $reverse = 0;
            unless ($reference) {
                # Reference objects are only created for forward-linking properties.  
                # Maybe this is a reverse_as-type property?  Try the joins data structure...
                my @joins = $delegated_property->_get_joins;
                foreach my $join ( @joins ) {
                    my @references = UR::Object::Reference->get(class_name   => $join->{'foreign_class'},
                                                                r_class_name => $join->{'source_class'});
                    if (@references == 1) {
                        $reverse = 1;
                        $reference = $references[0];
                        last;
                    } elsif (@references) {
                        Carp::confess(sprintf("Don't know what to do with more than one %d Reference objects between %s and %s",
                                               scalar(@references), $delegated_property->class_name, $join->{'foreign_class'}));
                    }
                }
                unless ($reference) {
                    # FIXME - should we just next instead of dying?
                    my $linking_property = $class_meta->property_meta_for_name($delegated_property->via);
                    Carp::confess(sprintf("No Reference link found between %s and %s", $delegated_property->class_name, $linking_property->data_type));
                }
            }

                
            my @ref_properties = $reference->get_property_links();
            my $property_getter = $reverse ? 'r_property_name' : 'property_name'; 
            foreach my $ref_property ( @ref_properties ) {
                next if ($seen_properties{$ref_property->$property_getter});
                my $ref_property_name = $ref_property->$property_getter;
                next unless ($rule_template->specifies_value_for($ref_property_name));

                my $ref_operator = $rule_template->operator_for($ref_property_name);
                $ref_operator ||= '=';

                push @secondary_params, $ref_property->r_property_name . ' ' . $ref_operator;
            }

            my $secondary_rule_template = UR::BoolExpr::Template->resolve($secondary_class, @secondary_params);

            # FIXME there should be a way to collect all the requests for the same datasource together...
            # FIXME - currently in the process of switching to object-based instead of class-based data sources
            # For now, data sources are still singleton objects, so this get() will work.  When we're fully on
            # regular-object-based data sources, then it'll probably change to UR::DataSource->get($secondary_data_source_id); 
            my $secondary_data_source = UR::DataSource->get($secondary_data_source_id) || $secondary_data_source_id->get();
            push @addl_loading_info,
                     $secondary_data_source,
                     [$delegated_property],
                     $secondary_rule_template;
        }
    }

    return ($primary_template, @addl_loading_info);
}


# Used by _create_secondary_loading_comparators to convert a rule against the primary data source
# to a rule that can be used against a secondary data source
# FIXME this might be made simpler be leaning on infer_property_value_from_rule()?
sub _create_secondary_rule_from_primary {
    my($self,$primary_rule, $delegated_properties, $secondary_rule_template) = @_;

    my @secondary_values;
    my %seen_properties;  # FIXME - we've already been over this list in _get_template_data_for_loading()...
    # FIXME - is there ever a case where @$delegated_properties will be more than one item?
    foreach my $property ( @$delegated_properties ) {
        my $value = $primary_rule->value_for($property->property_name);

        my $secondary_property_name = $property->to;
        my $pos = $secondary_rule_template->value_position_for_property_name($secondary_property_name);
        $secondary_values[$pos] = $value;
        $seen_properties{$property->property_name}++;

        my $reference = UR::Object::Reference->get(class_name => $property->class_name,
                                                   delegation_name => $property->via);
        my $reverse = 0;
        unless ($reference) {
            # FIXME - this code is almost exactly like the code in _get_template_data_for_loading
            my @joins = $property->_get_joins;
            foreach my $join ( @joins ) {
                my @references = UR::Object::Reference->get(class_name   => $join->{'foreign_class'},
                                                            r_class_name => $join->{'source_class'});
                if (@references == 1) {
                    $reverse = 1;
                    $reference = $references[0];
                    last;
                } elsif (@references) {
                    Carp::confess(sprintf("Don't know what to do with more than one %d Reference objects between %s and %s",
                                           scalar(@references), $property->class_name, $join->{'foreign_class'}));
                }
            }
        }
        next unless $reference;

        my @ref_properties = $reference->get_property_links();
        my $property_getter = $reverse ? 'r_property_name' : 'property_name';
        foreach my $ref_property ( @ref_properties ) {
            my $ref_property_name = $ref_property->$property_getter;
            next if ($seen_properties{$ref_property_name}++);
            $value = $primary_rule->value_for($ref_property_name);
            next unless $value;

            $pos = $secondary_rule_template->value_position_for_property_name($ref_property->r_property_name);
            $secondary_values[$pos] = $value;
        }
    }

    my $secondary_rule = $secondary_rule_template->get_rule_for_values(@secondary_values);

    return $secondary_rule;
}


# Since we'll be appending more "columns" of data to the listrefs returned by
# the primary datasource's query, we need to apply fixups to the column positions
# to all the secondary loading templates
# The column_position and object_num offsets needed for the next call of this method
# are returned
sub _fixup_secondary_loading_template_column_positions {
    my($self,$primary_loading_templates, $secondary_loading_templates, $column_position_offset, $object_num_offset) = @_;

    if (! defined($column_position_offset) or ! defined($object_num_offset)) {
        $column_position_offset = 0;
        foreach my $tmpl ( @{$primary_loading_templates} ) {
            $column_position_offset += scalar(@{$tmpl->{'column_positions'}});
        }
        $object_num_offset = scalar(@{$primary_loading_templates});
    }

    my $this_template_column_count;
    foreach my $tmpl ( @$secondary_loading_templates ) {
        foreach ( @{$tmpl->{'column_positions'}} ) {
            $_ += $column_position_offset;
        }
        foreach ( @{$tmpl->{'id_column_positions'}} ) {
            $_ += $column_position_offset;
        }
        $tmpl->{'object_num'} += $object_num_offset;

        $this_template_column_count += scalar(@{$tmpl->{'column_positions'}});
    }


    return ($column_position_offset + $this_template_column_count,
            $object_num_offset + scalar(@$secondary_loading_templates) );
}


# For queries that have to hit multiple data sources, this method creates two lists of
# closures.  The first is a list of object fabricators, where the loading templates
# have been given fixups to the column positions (see _fixup_secondary_loading_template_column_positions())
# The second is a list of closures for each data source (the @addl_loading_info stuff
# from _get_template_data_for_loading) that's able to compare the row loaded from the
# primary data source and see if it joins to a row from this secondary datasource's database
sub _create_secondary_loading_closures {
    my($self, $primary_template, $rule, @addl_loading_info) = @_;

    my $loading_templates = $primary_template->{'loading_templates'};

    # Make a mapping of property name to column positions returned by the primary query
    my %primary_query_column_positions;
    foreach my $tmpl ( @$loading_templates ) {
        my $property_name_count = scalar(@{$tmpl->{'property_names'}});
        for (my $i = 0; $i < $property_name_count; $i++) {
            my $property_name = $tmpl->{'property_names'}->[$i];
            my $pos = $tmpl->{'column_positions'}->[$i];
            $primary_query_column_positions{$property_name} = $pos;
        }
    }

    my @secondary_object_importers;
    my @addl_join_comparators;

    # used to shift the apparent column position of the secondary loading template info
    my ($column_position_offset,$object_num_offset);

    while (@addl_loading_info) {
        my $secondary_data_source = shift @addl_loading_info;
        my $this_ds_delegations = shift @addl_loading_info;
        my $secondary_rule_template = shift @addl_loading_info;

        my $secondary_rule = $self->_create_secondary_rule_from_primary (
                                              $rule,
                                              $this_ds_delegations,
                                              $secondary_rule_template,
                                       );
        $secondary_data_source = $secondary_data_source->resolve_data_sources_for_rule($secondary_rule);
        my $secondary_template = $self->_get_template_data_for_loading($secondary_data_source,$secondary_rule_template);

        # sets of triples where the first in the triple is the column index in the
        # $secondary_db_row (in the join_comparator closure below), the second is the
        # index in the $next_db_row.  And the last is a flag indicating if we should 
        # perform a numeric comparison.  This way we can preserve the order the comparisons
        # should be done in
        my @join_comparison_info;
        foreach my $property ( @$this_ds_delegations ) {
            # first, map column names in the joined class to column names in the primary class
            my %foreign_property_name_map;
            my @this_property_joins = $property->_get_joins();
            foreach my $join ( @this_property_joins ) {
                my @source_names = @{$join->{'source_property_names'}};
                my @foreign_names = @{$join->{'foreign_property_names'}};
                @foreign_property_name_map{@foreign_names} = @source_names;
            }

            # Now, find out which numbered column in the result query maps to those names
            my $secondary_loading_templates = $secondary_template->{'loading_templates'};
            foreach my $tmpl ( @$secondary_loading_templates ) {
                my $property_name_count = scalar(@{$tmpl->{'property_names'}});
                for (my $i = 0; $i < $property_name_count; $i++) {
                    my $property_name = $tmpl->{'property_names'}->[$i];
                    if ($foreign_property_name_map{$property_name}) {
                        # This is the one we're interested in...  Where does it come from in the primary query?
                        my $column_position = $tmpl->{'column_positions'}->[$i];

                        # What are the types involved?
                        my $primary_query_column_name = $foreign_property_name_map{$property_name};
                        my $primary_property_meta = UR::Object::Property->get(class_name => $primary_template->{'class_name'},
                                                                              property_name => $primary_query_column_name);
                        my $secondary_property_meta = UR::Object::Property->get(class_name => $secondary_template->{'class_name'},
                                                                                property_name => $property_name);

                        my $comparison_type;
                        if ($primary_property_meta->is_numeric && $secondary_property_meta->is_numeric) {
                            $comparison_type = 1;
                        } 

                        my $comparison_position;
                        if (exists $primary_query_column_positions{$primary_query_column_name} ) {
                            $comparison_position = $primary_query_column_positions{$primary_query_column_name};

                        } else {
                            # This isn't a real column we can get from the data source.  Maybe it's
                            # in the constant_property_names of the primary_loading_template?
                            unless (grep { $_ eq $primary_query_column_name}
                                    @{$loading_templates->[0]->{'constant_property_names'}}) {
                                die sprintf("Can't resolve datasource comparison to join %s::%s to %s:%s",
                                            $primary_template->{'class_name'}, $primary_query_column_name,
                                            $secondary_template->{'class_name'}, $property_name);
                            }
                            my $comparison_value = $rule->value_for($primary_query_column_name);
                            unless (defined $comparison_value) {
                                $comparison_value = $self->infer_property_value_from_rule($primary_query_column_name, $rule);
                            }
                            $comparison_position = \$comparison_value;
                        }
                        push @join_comparison_info, $column_position,
                                                    $comparison_position,
                                                    $comparison_type;
 

                    }
                }
            }
        }

        my $secondary_db_iterator = $secondary_data_source->create_iterator_closure_for_rule($secondary_rule);

        my $secondary_db_row;
        # For this closure, pass in the row we just loaded from the primary DB query.
        # This one will return the data from this secondary DB's row if the passed-in
        # row successfully joins to this secondary db iterator.  It returns an empty list
        # if there were no matches, and returns false if there is no more data from the query
        my $join_comparator = sub {
            my $next_db_row = shift;  # From the primary DB
            READ_DB_ROW:
            while(1) {
                return unless ($secondary_db_iterator);
                unless ($secondary_db_row) {
                    ($secondary_db_row) = $secondary_db_iterator->();
                    unless($secondary_db_row) {
                        # No more data to load 
                        $secondary_db_iterator = undef; 
                        return;
                    }
                }

                for (my $i = 0; $i < @join_comparison_info; $i += 3) {
                    my $secondary_column = $join_comparison_info[$i]; 
                    my $primary_column = $join_comparison_info[$i+1];
                    my $is_numeric = $join_comparison_info[$i+2];

                    my $comparison;
                    if (ref $primary_column) {
                        # This was one of those constant value items
                        if ($is_numeric) {
                            $comparison = $secondary_db_row->[$secondary_column] <=> $$primary_column;
                        } else {
                            $comparison = $secondary_db_row->[$secondary_column] cmp $$primary_column;
                        }
                    } else {
                        if ($join_comparison_info[$i+2]) {
                            $comparison = $secondary_db_row->[$secondary_column] <=> $next_db_row->[$primary_column];
                        } else {
                            $comparison = $secondary_db_row->[$secondary_column] cmp $next_db_row->[$primary_column];
                        }
                    }

                    if ($comparison < 0) {
                        # less than, get the next row from the secondary DB
                        $secondary_db_row = undef;
                        redo READ_DB_ROW;
                    } elsif ($comparison == 0) {
                        # This one was the same, keep looking at the others
                    } else {
                        # greater-than, there's no match for this primary DB row
                        return 0;
                    }
                }
                # All the joined columns compared equal, return the data
                return $secondary_db_row;
            }
        };
        Sub::Name::subname('UR::Context::__join_comparator(closure)__', $join_comparator);
        push @addl_join_comparators, $join_comparator;
 

        # And for the object importer/fabricator, here's where we need to shift the column order numbers
        # over, because these closures will be called after all the db iterators' rows are concatenated
        # together.  We also need to make a copy of the loading_templates list so as to not mess up the
        # class' notion of where the columns are
        # FIXME - it seems wasteful that we need to re-created this each time.  Look into some way of using 
        # the original copy that lives in $primary_template->{'loading_templates'}?  Somewhere else?
        my @secondary_loading_templates;
        foreach my $tmpl ( @{$secondary_template->{'loading_templates'}} ) {
            my %copy;
            foreach my $key ( keys %$tmpl ) {
                my $value_to_copy = $tmpl->{$key};
                if (ref($value_to_copy) eq 'ARRAY') {
                    $copy{$key} = [ @$value_to_copy ];
                } elsif (ref($value_to_copy) eq 'HASH') {
                    $copy{$key} = { %$value_to_copy };
                } else {
                    $copy{$key} = $value_to_copy;
                }
            }
            push @secondary_loading_templates, \%copy;
        }
            
        ($column_position_offset,$object_num_offset) =
                $self->_fixup_secondary_loading_template_column_positions($primary_template->{'loading_templates'},
                                                                          \@secondary_loading_templates,
                                                                          $column_position_offset,$object_num_offset);
 
        #my($secondary_rule_template,@secondary_values) = $secondary_rule->get_template_and_values();
        my @secondary_values = $secondary_rule->values();
        foreach my $secondary_loading_template ( @secondary_loading_templates ) {
            my $secondary_object_importer = $self->__create_object_fabricator_for_loading_template(
                                                       $secondary_loading_template,
                                                       $secondary_template,
                                                       $secondary_rule,
                                                       $secondary_rule_template,
                                                       \@secondary_values,
                                                       $secondary_data_source
                                                );
            next unless $secondary_object_importer;
            push @secondary_object_importers, $secondary_object_importer;
        }
                                                       

   }

    return (\@secondary_object_importers, \@addl_join_comparators);
}


# This returns an iterator that is used to bring objects in from an underlying
# context into this context.  It will not return any objects that already exist
# in the current context, even if the $db_iterator returns a row that belongs
# to an already-existing object
sub _create_import_iterator_for_underlying_context {
    my ($self, $rule, $dsx, $this_get_serial) = @_; 

    # TODO: instead of taking a data source, resolve this internally.
    # The underlying context itself should be responsible for its data sources.

    # Make an iterator for the primary data source.
    # Primary here meaning the one for the class we're explicitly requesting.
    # We may need to join to other data sources to complete the query.
    my ($db_iterator) 
        = $dsx->create_iterator_closure_for_rule($rule);

    my ($rule_template, @values) = $rule->template_and_values();
    my ($template_data,@addl_loading_info) = $self->_get_template_data_for_loading($dsx,$rule_template);
    my $class_name = $template_data->{class_name};

    my $group_by = $rule_template->group_by;
    my $order_by = $rule_template->order_by;

    if (my $sub_typing_property) {
        # When the rule has a property specified which indicates a specific sub-type, catch this and re-call
        # this method recursively with the specific subclass name.
        my ($rule_template, @values) = $rule->template_and_values();
        my $rule_template_specifies_value_for_subtype   = $template_data->{rule_template_specifies_value_for_subtype};
        my $class_table_name                            = $template_data->{class_table_name};
        #my @type_names_under_class_with_no_table        = @{ $template_data->{type_names_under_class_with_no_table} };
   
        warn "Implement me carefully";
        
        if ($rule_template_specifies_value_for_subtype) {
            #$DB::single = 1;
            my $sub_classification_meta_class_name          = $template_data->{sub_classification_meta_class_name};
            my $value = $rule->value_for($sub_typing_property);
            my $type_obj = $sub_classification_meta_class_name->get($value);
            if ($type_obj) {
                my $subclass_name = $type_obj->subclass_name($class_name);
                if ($subclass_name and $subclass_name ne $class_name) {
                    #$rule = $subclass_name->define_boolexpr($rule->params_list, $sub_typing_property => $value);
                    $rule = UR::BoolExpr->resolve_normalized($subclass_name, $rule->params_list, $sub_typing_property => $value);
                    return $self->_create_import_iterator_for_underlying_context($rule,$dsx,$this_get_serial);
                }
            }
            else {
                die "No $value for $class_name?\n";
            }
        }
        elsif (not $class_table_name) {
            #$DB::single = 1;
            # we're in a sub-class, and don't have the type specified
            # check to make sure we have a table, and if not add to the filter
            #my $rule = $class_name->define_boolexpr(
            #    $rule_template->get_rule_for_values(@values)->params_list, 
            #    $sub_typing_property => (@type_names_under_class_with_no_table > 1 ? \@type_names_under_class_with_no_table : $type_names_under_class_with_no_table[0]),
            #);
            die "No longer supported!";
            my $rule = UR::BoolExpr->resolve(
                           $class_name,
                           $rule_template->get_rule_for_values(@values)->params_list,
                           #$sub_typing_property => (@type_names_under_class_with_no_table > 1 ? \@type_names_under_class_with_no_table : $type_names_under_class_with_no_table[0]),
                        );
            return $self->_create_import_iterator_for_underlying_context($rule,$dsx,$this_get_serial)
        }
        else {
            # continue normally
            # the logic below will handle sub-classifying each returned entity
        }
    }
    
    
    my $loading_templates                           = $template_data->{loading_templates};
    my $sub_typing_property                         = $template_data->{sub_typing_property};
    my $next_db_row;
    my $rows = 0;                                   # number of rows the query returned
    
    my $recursion_desc                              = $template_data->{recursion_desc};
    my $rule_template_without_recursion_desc;
    my $rule_without_recursion_desc;
    if ($recursion_desc) {
        $rule_template_without_recursion_desc        = $template_data->{rule_template_without_recursion_desc};
        $rule_without_recursion_desc                 = $rule_template_without_recursion_desc->get_rule_for_values(@values);    
    }
    
    my $needs_further_boolexpr_evaluation_after_loading = $template_data->{'needs_further_boolexpr_evaluation_after_loading'};
    
    my %subordinate_iterator_for_class;
    
    # instead of making just one import iterator, we make one per loading template
    # we then have our primary iterator use these to fabricate objects for each db row
    my @object_fabricators;
    if ($group_by) {
        # returning sets instead of instance objects...
        my $set_class = $class_name . '::Set';
        my $logic_type = $rule_template->logic_type;
        my @base_property_names = $rule_template->_property_names;
        
        my @non_aggregate_properties = @$group_by;
        my @aggregate_properties = ('count'); # TODO: make non-hard-coded
        my $division_point = $#non_aggregate_properties;
    
        my $template = UR::BoolExpr::Template->get_by_subject_class_name_logic_type_and_logic_detail(
            $class_name,
            'And',
            join(",", @base_property_names, @non_aggregate_properties),
        );
        push @object_fabricators, sub {
            my $row = $_[0];
            # my $ss_rule = $template->get_rule_for_values(@values, @$row[0..$division_point]);
            # not sure why the above gets an error but this doesn't...
            my @a = @$row[0..$division_point];
            my $ss_rule = $template->get_rule_for_values(@values, @a); 
            my $set = $set_class->get($ss_rule->id);
            unless ($set) {
                die "Failed to fabricate $set_class for rule $ss_rule!";
            }
            @$set{@aggregate_properties} = @$row[$division_point+1..$#$row];
            return $set;
        };
    }
    else {
        # regular instances
        for my $loading_template (@$loading_templates) {
            my $object_fabricator = 
                $self->__create_object_fabricator_for_loading_template(
                    $loading_template, 
                    $template_data,
                    $rule,
                    $rule_template,
                    \@values,
                    $dsx,
                );
            next unless $object_fabricator;
            unshift @object_fabricators, $object_fabricator;
        }
    }

    # For joins across data sources, we need to create importers/fabricators for those
    # classes, as well as callbacks used to perform the equivalent of an SQL join in
    # UR-space
    my @addl_join_comparators;
    if (@addl_loading_info) {
        if ($group_by) {
            die "cross-datasource group-by is not supported yet!";
        }
        my($addl_object_fabricators, $addl_join_comparators) =
                $self->_create_secondary_loading_closures( $template_data,
                                                           $rule,
                                                           @addl_loading_info
                                                      );

        unshift @object_fabricators, @$addl_object_fabricators;
        push @addl_join_comparators, @$addl_join_comparators;
    }

    # Insert the key into all_objects_are_loaded to indicate that when we're done loading, we'll
    # have everything
    if ($template_data->{'rule_matches_all'} and not $group_by) {
        $class_name->all_objects_are_loaded(undef);
    }

    #my $is_monitor_query = $self->monitor_query();

    # Make the iterator we'll return.
    my $underlying_context_iterator = sub {
        my $object;
        
        LOAD_AN_OBJECT:
        until ($object) { # note that we return directly when the db is out of data
            
            my ($next_db_row);
            ($next_db_row) = $db_iterator->() if ($db_iterator);

            unless ($next_db_row) {
                if ($rows == 0) {
                    # if we got no data at all from the sql then we give a status
                    # message about it and we update all_params_loaded to indicate
                    # that this set of parameters yielded 0 objects
                    
                    my $rule_template_is_id_only = $template_data->{rule_template_is_id_only};
                    if ($rule_template_is_id_only) {
                        my $id = $rule->value_for_id;
                        $UR::Context::all_objects_loaded->{$class_name}->{$id} = undef;
                    }
                    else {
                        my $rule_id = $rule->id;
                        $UR::Context::all_params_loaded->{$class_name}->{$rule_id} = 0;
                    }
                }
                
                if ( $template_data->{rule_matches_all} ) {
                    # No parameters.  We loaded the whole class.
                    # Doing a load w/o a specific ID w/o custom SQL loads the whole class.
                    # Set a flag so that certain optimizations can be made, such as 
                    # short-circuiting future loads of this class.        
                    #
                    # If the key still exists in the all_objects_are_loaded hash, then
                    # we can set it to true.  This is needed in the case where the user
                    # gets an iterator for all the objects of some class, but unloads
                    # one or more of the instances (be calling unload or through the 
                    # cache pruner) before the iterator completes.  If so, _delete_object()
                    # will have removed the key from the hash
                    if (exists($UR::Context::all_objects_are_loaded->{$class_name})) {
                        $class_name->all_objects_are_loaded(1);
                    }
                }
                
                if ($recursion_desc) {
                    my @results = $class_name->is_loaded($rule_without_recursion_desc);
                    $UR::Context::all_params_loaded->{$class_name}{$rule_without_recursion_desc->id} = scalar(@results);
                    for my $object (@results) {
                        $object->{load}{param_key}{$class_name}{$rule_without_recursion_desc->id}++;
                    }
                }
                
                # Apply changes to all_params_loaded that each importer has collected
                foreach (@object_fabricators) {
                    $_->finalize if ref($_) ne 'CODE';
                }
                
                # If the SQL for the subclassed items was constructed properly, then each
                # of these iterators should be at the end, too.  Call them one more time
                # so they'll finalize their object fabricators.
                foreach my $class ( keys %subordinate_iterator_for_class ) {
                    my $obj = $subordinate_iterator_for_class{$class}->();
                    if ($obj) {
                        # The last time this happened, it was because a get() was done on an abstract
                        # base class with only 'id' as a param.  When the subclassified rule was
                        # turned into SQL in UR::DataSource::RDBMS::_generate_template_data_for_loading()
                        # it removed that one 'id' filter, since it assummed any class with more than
                        # one ID property (usually classes have a named whatever_id property, and an alias 'id'
                        # property) will have a rule that covered both ID properties
                        warn "Leftover objects in subordinate iterator for $class.  This shouldn't happen, but it's not fatal...";
                        while ($obj = $subordinate_iterator_for_class{$class}->()) {1;}
                    }
                }

                return;
            }
            
            # we count rows processed mainly for more concise sanity checking
            $rows++;

            # For multi-datasource queries, does this row successfully join with all the other datasources?
            #
            # Normally, the policy is for the data source query to return (possibly) more than what you
            # asked for, and then we'd cache everything that may have been loaded.  In this case, we're
            # making the choice not to.  Reason being that a join across databases is likely to involve
            # a lot of objects, and we don't want to be stuffing our object cache with a lot of things
            # we're not interested in.  FIXME - in order for this to be true, then we could never query
            # these secondary data sources against, say, a calculated property because we're never turning
            # them into objects.  FIXME - fix this by setting the $needs_further_boolexpr_evaluation_after_loading
            # flag maybe?
            my @secondary_data;
            foreach my $callback (@addl_join_comparators) {
                # FIXME - (no, not another one...) There's no mechanism for duplicating SQL join's
                # behavior where if a row from a table joins to 2 rows in the secondary table, the 
                # first table's data will be in the result set twice.
                my $secondary_db_row = $callback->($next_db_row);
                unless (defined $secondary_db_row) {
                    # That data source has no more data, so there can be no more joins even if the
                    # primary data source has more data left to read
                    return;
                }
                unless ($secondary_db_row) {  
                    # It returned 0
                    # didn't join (but there is still more data we can read later)... throw this row out.
                    $object = undef;
                    redo LOAD_AN_OBJECT;
                }
                # $next_db_row is a read-only value from DBI, so we need to track our additional 
                # data seperately and smash them together before the object importer is called
                push(@secondary_data, @$secondary_db_row);
            }
            
            # get one or more objects from this row of results
            my $re_iterate = 0;
            my @imported;
            for my $object_fabricator (@object_fabricators) {
                # The usual case is that the query is just against one data source, and so the importer
                # callback is just given the row returned from the DB query.  For multiple data sources,
                # we need to smash together the primary and all the secondary lists
                my $imported_object;

                #my $object_creation_time;
                #if ($is_monitor_query) {
                #    $object_creation_time = Time::HiRes::time();
                #}

                if (@secondary_data) {
                    $imported_object = $object_fabricator->([@$next_db_row, @secondary_data]);
                } else { 
                    $imported_object = $object_fabricator->($next_db_row);
                }
                    
                #if ($is_monitor_query) {
                #    $self->_log_query_for_rule($class_name, $rule, sprintf("QUERY: object fabricator took %.4f s",Time::HiRes::time() - $object_creation_time));
                #}

                if ($imported_object and not ref($imported_object)) {
                    # object requires sub-classsification in a way which involves different db data.
                    $re_iterate = 1;
                }
                push @imported, $imported_object;
            }
            
            $object = $imported[-1];
            my $this_object_was_already_cached = defined($object)
                                              && ref($object)
                                              && exists($object->{'__get_serial'});

            foreach my $obj (@imported) {
                # The object importer will return undef for an object if no object
                # got created for that $next_db_row, and will return a string if the object
                # needs to be subclassed before being returned.  Don't put serial numbers on
                # these
                next unless (defined($obj) && ref($obj));

                $obj->{'__get_serial'} = $this_get_serial;
            }

            if ($this_object_was_already_cached) {
                # Don't return objects that already exist in the current context
                # FIXME - when we can stack contexts in the same application, and the 
                # loaded context is recorded on the object, use that context as the
                # test above instead of the existence of a __get_serial
                $object = undef;
                redo LOAD_AN_OBJECT;
            }
            
            if ($re_iterate) {
                # It is possible that one or more objects go into subclasses which require more
                # data than is on the results row.  For each subclass (or set of subclasses),
                # we make a more specific, subordinate iterator to delegate-to.
 
                my $subclass_name = $object;

                unless (grep { not ref $_ } @imported[0..$#imported-1]) {
                    my $subclass_meta = UR::Object::Type->get(class_name => $subclass_name);
                    my $table_subclass = $subclass_meta->most_specific_subclass_with_table();
                    my $sub_iterator = $subordinate_iterator_for_class{$table_subclass};
                    unless ($sub_iterator) {
                        #print "parallel iteration for loading $subclass_name under $class_name!\n";
                        my $sub_classified_rule_template = $rule_template->sub_classify($subclass_name);
                        my $sub_classified_rule = $sub_classified_rule_template->get_normalized_rule_for_values(@values);
                        $sub_iterator 
                            = $subordinate_iterator_for_class{$table_subclass} 
                                = $self->_create_import_iterator_for_underlying_context($sub_classified_rule,$dsx,$this_get_serial);
                    }
                    ($object) = $sub_iterator->();
                    if (! defined $object) {
                        # the newly subclassed object 
                        redo LOAD_AN_OBJECT;
                    }
                
                #unless ($object->id eq $id) {
                #    Carp::cluck("object id $object->{id} does not match expected id $id");
                #    $DB::single = 1;
                #    print "";
                #    die;
                #}
               }
            } # end of handling a possible subordinate iterator delegate
            
            unless ($object) {
                redo LOAD_AN_OBJECT;
            }
            
            unless ($group_by) {
                if ( (ref($object) ne $class_name) and (not $object->isa($class_name)) ) {
                    $object = undef;
                    redo LOAD_AN_OBJECT;
                }
            }
            
            if ($needs_further_boolexpr_evaluation_after_loading and not $rule->evaluate($object)) {
                $object = undef;
                redo LOAD_AN_OBJECT;
            }
            
        } # end of loop until we have a defined object to return
        
        return $object;
    };
    
    Sub::Name::subname('UR::Context::__underlying_context_iterator(closure)__', $underlying_context_iterator);
    return $underlying_context_iterator;
}


# Called by the object fabricator closure that's created in __create_object_fabricator_for_loading_template
# below.  This will check the data in an existing cached object, compare it with data that's currently being
# loaded in from the database, and depending on the data:
# 1) update the current value for the property
# 2) update the db_committed/db_saved_uncommitted
# 3) throw an exception if there are conflicting data changes
# Returns true if $existing_object has been changed since it was loaded.  This is used in one of the
# branches of the object fabricator.

sub __merge_db_data_with_existing_object {
    my($self, $class_name, $existing_object, $pending_db_object_data, $property_names) = @_;

    my $expected_db_data;
    if (exists $existing_object->{'db_saved_uncommitted'}) {
        $expected_db_data = $existing_object->{'db_saved_uncommitted'};

    } elsif (exists $existing_object->{'db_committed'}) {
        $expected_db_data = $existing_object->{'db_committed'};

    } else {
        my $id = $existing_object->id;
        Carp::croak("$class_name ID '$id' has just been loaded, but it exists in the application as a new unsaved object!\nDump: " . Data::Dumper::Dumper($existing_object) . "\n");
    }

    my $different = 0;
    my $conflict = undef;

    foreach my $property ( @$property_names ) {
        no warnings 'uninitialized';

        next unless (exists $existing_object->{$property});   # All direct properties are stored in the same-named hash key, right?

        my $object_value      = $existing_object->{$property};
        my $db_value          = $pending_db_object_data->{$property};
        my $expected_db_value = $expected_db_data->{$property};

        if ($object_value ne $expected_db_value) {
            $different = 1;
        }

        
        if ( $object_value eq $db_value              # current value matches DB value
             or
             ($object_value eq $expected_db_value)   # current value hasn't changed since it was loaded from the DB
             or
             ($db_value eq $expected_db_value)       # DB value matches what it was when we loaded it from the DB
        ) {
            # no conflict.  Check the next one
            next;
        } else {
            $conflict = $property;
            last;
        }
    }

    if (defined $conflict) {
        # conflicting change!
        # Since the user could be catching this exception, go ahead and update the
        # object's notion of what is in the database
        my %old_dbc = %$expected_db_data;
        @$expected_db_data{@$property_names} = @$pending_db_object_data{@$property_names};

        my $old_value = defined($old_dbc{$conflict})
                        ? "'" . $old_dbc{$conflict} . "'"
                        : '(undef)';
        my $new_db_value = defined($pending_db_object_data->{$conflict})
                        ? "'" . $pending_db_object_data->{$conflict} . "'"
                        : '(undef)';
        my $new_obj_value = defined($existing_object->{$conflict})
                        ? "'" . $existing_object->{$conflict} . "'"
                        : '(undef)';

        my $obj_id = $existing_object->id;

        Carp::croak("\nA change has occurred in the database for $class_name property '$conflict' on object ID $obj_id from $old_value to $new_db_value.\n"
                    . "At the same time, this application has made a change to that value to $new_obj_value.\n\n"
                    . "The application should lock data which it will update and might be updated by other applications.");

    }
 
    # No conflicts.  Update db_committed and db_saved_uncommitted based on the DB data
    %$expected_db_data = (%$expected_db_data, %$pending_db_object_data);

    if (! $different) {
        # The object has no local changes.  Go ahead and update the current value, too
        foreach my $property ( @$property_names ) {
            no warnings 'uninitialized';
            next if ($existing_object->{$property} eq $pending_db_object_data->{$property});

            $existing_object->$property($pending_db_object_data->{$property});
        }
    }

    return $different;
}



sub __create_object_fabricator_for_loading_template {
    my ($self, $loading_template, $template_data, $rule, $rule_template, $values, $dsx) = @_;

    my @values = @$values;

    my $class_name                                  = $loading_template->{final_class_name};
    #$class_name or Carp::croak("No final_class_name in loading template?");
    unless ($class_name) {
        #Carp::carp("No final_class_name in loading template for rule $rule");
        return;   # This join doesn't result in an object? - i think this happens when you do a get() with -hints
    }
    
    my $class_meta                                  = $class_name->__meta__;
    my $class_data                                  = $dsx->_get_class_data_for_loading($class_meta);
    my $class = $class_name;
    
    my $ghost_class                                 = $class_data->{ghost_class};
    my $sub_classification_meta_class_name          = $class_data->{sub_classification_meta_class_name};
    my $subclassify_by            = $class_data->{subclassify_by};
    my $sub_classification_method_name              = $class_data->{sub_classification_method_name};

    # FIXME, right now, we don't have a rule template for joined entities...
    
    my $rule_template_id                            = $template_data->{rule_template_id};
    my $rule_template_without_recursion_desc        = $template_data->{rule_template_without_recursion_desc};
    my $rule_template_id_without_recursion_desc     = $template_data->{rule_template_id_without_recursion_desc};
    my $rule_matches_all                            = $template_data->{rule_matches_all};
    my $rule_template_is_id_only                    = $template_data->{rule_template_is_id_only};
    my $rule_specifies_id                           = $template_data->{rule_specifies_id};
    my $rule_template_specifies_value_for_subtype   = $template_data->{rule_template_specifies_value_for_subtype};

    my $recursion_desc                              = $template_data->{recursion_desc};
    my $recurse_property_on_this_row                = $template_data->{recurse_property_on_this_row};
    my $recurse_property_referencing_other_rows     = $template_data->{recurse_property_referencing_other_rows};

    my $needs_further_boolexpr_evaluation_after_loading = $template_data->{'needs_further_boolexpr_evaluation_after_loading'};

    my $rule_id = $rule->id;    
    my $rule_without_recursion_desc = $rule_template_without_recursion_desc->get_rule_for_values(@values);    

    my $loading_base_object;
    if ($loading_template == $template_data->{loading_templates}[0]) {
        $loading_base_object = 1;
    }
    else {
        $loading_base_object = 0;
        $needs_further_boolexpr_evaluation_after_loading = 0;
    }
    
    my %subclass_is_safe_for_re_bless;
    my %subclass_for_subtype_name;  
    my %recurse_property_value_found;
    
    my @property_names      = @{ $loading_template->{property_names} };
    my @id_property_names   = @{ $loading_template->{id_property_names} };
    my @column_positions    = @{ $loading_template->{column_positions} };
    my @id_positions        = @{ $loading_template->{id_column_positions} };
    my $multi_column_id     = (@id_positions > 1 ? 1 : 0);
    my $composite_id_resolver = $class_meta->get_composite_id_resolver;
    
    # The old way of specifying that some values were constant for all objects returned
    # by a get().  The data source would wrap the method that builds the loading template
    # and wedge in some constant_property_names.  The new way is to add columns to the
    # loading template, and then add the values onto the list returned by the data source
    # iterator.  
    my %initial_object_data;
    if ($loading_template->{constant_property_names}) {
        my @constant_property_names  = @{ $loading_template->{constant_property_names} };
        my @constant_property_values = map { $rule->value_for($_) } @constant_property_names;
        @initial_object_data{@constant_property_names} = @constant_property_values;
    }

    my $rule_class_name = $rule_template->subject_class_name;
    my $load_class_name = $class;
    # $rule can contain params that may not apply to the subclass that's currently loading.
    # define_boolexpr() in array context will return the portion of the rule that actually applies
    #my($load_rule, undef) = $load_class_name->define_boolexpr($rule->params_list);
    my($load_rule, undef) = UR::BoolExpr->resolve($load_class_name, $rule->params_list);
    my $load_rule_id = $load_rule->id;

    my @rule_properties_with_in_clauses =
        grep { $rule_template_without_recursion_desc->operator_for($_) eq '[]' } 
             $rule_template_without_recursion_desc->_property_names;

    #my $rule_template_without_in_clause = $rule_template_without_recursion_desc;
    my $rule_template_without_in_clause;
    if (@rule_properties_with_in_clauses) {
        my $rule_template_id_without_in_clause = $rule_template_without_recursion_desc->id;
        foreach my $property_name ( @rule_properties_with_in_clauses ) {
            # FIXME - removing and re-adding the filter should have the same effect as the substitute below,
            # but the two result in different rules in the end.
            #$rule_template_without_in_clause = $rule_template_without_in_clause->remove_filter($property_name);
            #$rule_template_without_in_clause = $rule_template_without_in_clause->add_filter($property_name);
            $rule_template_id_without_in_clause =~ s/($property_name) \[\]/$1/;
        }
        $rule_template_without_in_clause = UR::BoolExpr::Template->get($rule_template_id_without_in_clause);
    }


    # If the rule has hints, we'll be loading more data than is being returned.  Set up some stuff so
    # we can mark in all_params_loaded that these other things got loaded, too
    my %rule_hints;
    if (!$loading_base_object && $rule_template->hints) {
        #$DB::single=1; 
        my $query_class_meta = $rule_template->subject_class_name->__meta__;
        foreach my $hint ( @{ $rule_template->hints } ) {
            my $delegated_property_meta = $query_class_meta->property_meta_for_name($hint);
            next unless $delegated_property_meta;
            foreach my $join ( $delegated_property_meta->_get_joins ) {
                next unless ($join->{'foreign_class'} eq $loading_template->{'data_class_name'});

                # Is this the equivalent of loading by the class' ID?
                my $foreign_class_meta = $join->{'foreign_class'}->__meta__;
                my %join_properties = map { $_ => 1 } @{$join->{'foreign_property_names'}};
                my $join_has_all_id_props = 1;
                foreach my $foreign_id_prop ( $foreign_class_meta->all_id_property_metas ) {
                    next if ($foreign_id_prop->class_name eq 'UR::Object');  # Skip the manufactured property called id
                    next if (delete $join_properties{ $foreign_id_prop->property_name });
                    # If we get here, there's an ID property that isn't mentioned in the join properties
                    $join_has_all_id_props = 0;
                    last;
                }
                next if ( $join_has_all_id_props and ! scalar(keys %join_properties));

                $rule_hints{$hint} ||= [];
                my $hint_rule_tmpl = UR::BoolExpr::Template->resolve($join->{'foreign_class'}, 
                                                                                          @{$join->{'foreign_property_names'}});
                push @{$rule_hints{$hint}}, [ [@{$join->{'foreign_property_names'}}] , $hint_rule_tmpl];
            }
        }
    }
    
    # This is a local copy of what we want to put in all_params_loaded, when the object fabricator is
    # finalized
    my $all_params_loaded_items = {};

    my $object_fabricator = sub {
        my $next_db_row = $_[0];
        
        my $pending_db_object_data = { %initial_object_data };
        @$pending_db_object_data{@property_names} = @$next_db_row[@column_positions];
        
        # resolve id
        my $pending_db_object_id;
        if ($multi_column_id) {
            $pending_db_object_id = $composite_id_resolver->(@$pending_db_object_data{@id_property_names})
        }
        else {
            $pending_db_object_id = $pending_db_object_data->{$id_property_names[0]};
        }
        
        unless (defined $pending_db_object_id) {
            #$DB::single = $DB::stopper;
            return undef;
            Carp::confess(
                "no id found in object data for $class_name?\n" 
                . Data::Dumper::Dumper($pending_db_object_data)
            );
        }
        
        my $pending_db_object;
        
        # skip if this object has been deleted but not committed
        do {
            no warnings;
            if ($UR::Context::all_objects_loaded->{$ghost_class}{$pending_db_object_id}) {
                return;
                #$pending_db_object = undef;
                #redo;
            }
        };

        # Handle the object based-on whether it is already loaded in the current context.
        if ($pending_db_object = $UR::Context::all_objects_loaded->{$class}{$pending_db_object_id}) {
            $self->__merge_db_data_with_existing_object($class, $pending_db_object, $pending_db_object_data, \@property_names);

        }
        else {
            # Handle the case in which the object is completely new in the current context.
            
            # Create a new object for the resultset row
            $pending_db_object = bless { %$pending_db_object_data, id => $pending_db_object_id }, $class;
            $pending_db_object->{db_committed} = $pending_db_object_data;
            
            # determine the subclass name for classes which automatically sub-classify
            my $subclass_name;
            if (    
                    (
                        $sub_classification_method_name
                        or $subclassify_by
                        or $sub_classification_meta_class_name 
                    )
                    and
                    (ref($pending_db_object) eq $class) # not already subclased  
            ) {
                if ($sub_classification_method_name) {
                    $subclass_name = $class->$sub_classification_method_name($pending_db_object);
                    unless ($subclass_name) {
                        my $pending_obj_id = eval { $pending_db_object->id };
                        Carp::confess(
                            "Object with id '$pending_obj_id' loaded as abstract class $class failed to subclassify itself using method "
                            . $sub_classification_method_name
                        );
                    }
                }
                elsif ($sub_classification_meta_class_name) {
                    #$DB::single = 1;
                    # Group objects requiring reclassification by type, 
                    # and catch anything which doesn't need reclassification.
                    
                    my $subtype_name = $pending_db_object->$subclassify_by;
                    
                    $subclass_name = $subclass_for_subtype_name{$subtype_name};
                    unless ($subclass_name) {
                        my $type_obj = $sub_classification_meta_class_name->get($subtype_name);
                        
                        unless ($type_obj) {
                            # The base type may give the final subclass, or an intermediate
                            # either choice has trade-offs, but we support both.
                            # If an intermediate subclass is specified, that subclass
                            # will join to a table with another field to indicate additional 
                            # subclassing.  This means we have to do this part the hard way.
                            # TODO: handle more than one level.
                            my @all_type_objects = $sub_classification_meta_class_name->get();
                            for my $some_type_obj (@all_type_objects) {
                                my $some_subclass_name = $some_type_obj->subclass_name($class);
                                unless (UR::Object::Type->get($some_subclass_name)->is_abstract) {
                                    next;
                                }                
                                my $some_subclass_meta = $some_subclass_name->__meta__;
                                my $some_subclass_type_class = 
                                                $some_subclass_meta->sub_classification_meta_class_name;
                                if ($type_obj = $some_subclass_type_class->get($subtype_name)) {
                                    # this second-tier subclass works
                                    last;
                                }       
                                else {
                                    # try another subclass, and check the subclasses under it
                                    #print "skipping $some_subclass_name: no $subtype_name for $some_subclass_type_class\n";
                                }
                            }
                        }
                        
                        if ($type_obj) {                
                            $subclass_name = $type_obj->subclass_name($class);
                        }
                        else {
                            warn "Failed to find $class_name sub-class for type '$subtype_name'!";
                            $subclass_name = $class_name;
                        }
                        
                        unless ($subclass_name) {
                            Carp::confess(
                                "Failed to sub-classify $class using " 
                                . $type_obj->class
                                . " '" . $type_obj->id . "'"
                            );
                        }        
                        
                        $subclass_name->class;
                    }
                    $subclass_for_subtype_name{$subtype_name} = $subclass_name;
                }
                else {
                    $subclass_name = $pending_db_object->$subclassify_by;
                    unless ($subclass_name) {
                        Carp::croak("Failed to sub-classify $class while loading; calling method "
                                    . "'$subclassify_by' returned false.  Relevant object data: "
                                    . Data::Dumper::Dumper($pending_db_object));
                    }
                }

                # note: we check this again with the real base class, but this keeps junk objects out of the core hash
                unless ($subclass_name->isa($class)) {
                    # We may have done a load on the base class, and not been able to use properties to narrow down to the correct subtype.
                    # The resultset returned more data than we needed, and we're filtering out the other subclasses here.
                    return;
                }
            }
            else {
                # regular, non-subclassifier
                $subclass_name = $class;
            }
            
            # store the object
            # note that we do this on the base class even if we know it's going to be put into a subclass below
            $UR::Context::all_objects_loaded->{$class}{$pending_db_object_id} = $pending_db_object;
            $UR::Context::all_objects_cache_size++;
            #$pending_db_object->__signal_change__('_create_object', $pending_db_object_id)
            
            # If we're using a light cache, weaken the reference.
            if ($UR::Context::light_cache and substr($class,0,5) ne 'App::') {
                Scalar::Util::weaken($UR::Context::all_objects_loaded->{$class_name}->{$pending_db_object_id});
            }
            
            # Make a note in all_params_loaded (essentially, the query cache) that we've made a
            # match on this rule, and some equivalent rules
            if ($loading_base_object and not $rule_specifies_id) {
                if ($rule_class_name ne $load_class_name) {
                    $pending_db_object->{load}{param_key}{$load_class_name}{$load_rule_id}++;
                    $UR::Context::all_params_loaded->{$load_class_name}{$load_rule_id} = undef;
                    $all_params_loaded_items->{$load_class_name}{$load_rule_id}++;
                }
                $pending_db_object->{load}{param_key}{$rule_class_name}{$rule_id}++;
                $UR::Context::all_params_loaded->{$rule_class_name}{$rule_id} = undef;
                $all_params_loaded_items->{$rule_class_name}{$rule_id}++;

                if (@rule_properties_with_in_clauses) {
                    # FIXME - confirm that all the object properties are filled in at this point, right?
                    my @values = @$pending_db_object{@rule_properties_with_in_clauses};
                    #foreach my $property_name ( @rule_properties_with_in_clauses ) {
                    #    push @values, $pending_db_object->$property_name;
                    #}
                    my $r = $rule_template_without_in_clause->get_normalized_rule_for_values(@values);
                    
                    $UR::Context::all_params_loaded->{$rule_class_name}{$r->id} = undef;
                    $all_params_loaded_items->{$rule_class_name}{$r->id}++;
                }
            }
            
            unless ($subclass_name eq $class) {
                # we did this above, but only checked the base class
                my $subclass_ghost_class = $subclass_name->ghost_class;
                if ($UR::Context::all_objects_loaded->{$subclass_ghost_class}{$pending_db_object_id}) {
                    # We put it in the object cache a few lines above.
                    # FIXME - why not wait until we know we're keeping it before putting it in there?
                    delete $UR::Context::all_objects_loaded->{$class}{$pending_db_object_id};
                    $UR::Context::all_objects_cache_size--;
                    return;
                    #$pending_db_object = undef;
                    #redo;
                }
                
                my $re_bless = $subclass_is_safe_for_re_bless{$subclass_name};
                if (not defined $re_bless) {
                    $re_bless = $dsx->_class_is_safe_to_rebless_from_parent_class($subclass_name, $class);
                    $re_bless ||= 0;
                    $subclass_is_safe_for_re_bless{$subclass_name} = $re_bless;
                }
                
                my $loading_info;
                if ($re_bless) {
                    # Performance shortcut.
                    # These need to be subclassed, but there is no added data to load.
                    # Just remove and re-add from the core data structure.
                    my $already_loaded = $subclass_name->is_loaded($pending_db_object->id);

                    my $different;
                    my $merge_exception;
                    if ($already_loaded) {
                        eval { $different = $self->__merge_db_data_with_existing_object($class, $already_loaded, $pending_db_object_data, \@property_names) };
                        $merge_exception = $@;
                    }
                    
                    if ($already_loaded and !$different and !$merge_exception) {
                        if ($pending_db_object == $already_loaded) {
                            print "ALREADY LOADED SAME OBJ?\n";
                            $DB::single = 1;
                            die "The loaded object already exists in its target subclass?!";
                        }
                        
                        if ($loading_base_object) {
                            # Get our records about loading this object
                            $loading_info = $dsx->_get_object_loading_info($pending_db_object);
                            
                            # Transfer the load info for the load we _just_ did to the subclass too.
                            $loading_info->{$subclass_name} = $loading_info->{$class};
                            $loading_info = $dsx->_reclassify_object_loading_info_for_new_class($loading_info,$subclass_name);
                        }
                        
                        # This will wipe the above data from the object and the contex...
                        #$pending_db_object->unload;
                        delete $UR::Context::all_objects_loaded->{$class}->{$pending_db_object_id};
                        
                        if ($loading_base_object) {
                            # ...now we put it back for both.
                            $dsx->_add_object_loading_info($already_loaded, $loading_info);
                            $dsx->_record_that_loading_has_occurred($loading_info);
                        }
                        
                        $pending_db_object = $already_loaded;
                    }
                    else {
                        if ($loading_base_object) {
                            $loading_info = $dsx->_get_object_loading_info($pending_db_object);
                            $dsx->_record_that_loading_has_occurred($loading_info);
                            $loading_info->{$subclass_name} = delete $loading_info->{$class};
                            $loading_info = $dsx->_reclassify_object_loading_info_for_new_class($loading_info,$subclass_name);
                        }
                        
                        my $prev_class_name = $pending_db_object->class;
                        my $id = $pending_db_object->id;
                        $pending_db_object->__signal_change__("unload");
                        delete $UR::Context::all_objects_loaded->{$prev_class_name}->{$id};
                        delete $UR::Context::all_objects_are_loaded->{$prev_class_name};
                        if ($merge_exception) {
                            # Now that we've removed traces of the incorrectly-subclassed $pending_db_object,
                            # we can pass up any exception generated in __merge_db_data_with_existing_object
                            die $merge_exception;
                        }
                        if ($already_loaded) {
                            # The new object should replace the old object.  Since other parts of the user's program
                            # may have references to this object, we need to copy the values from the new object into
                            # the existing cached object
                            $pending_db_object = $already_loaded;
                        } else {
                            # This is a completely new object
                            $UR::Context::all_objects_loaded->{$subclass_name}->{$id} = $pending_db_object;
                        }
                        bless $pending_db_object, $subclass_name;
                        $pending_db_object->__signal_change__("load");
                        
                        $dsx->_add_object_loading_info($pending_db_object, $loading_info);
                        $dsx->_record_that_loading_has_occurred($loading_info);
                    }
                }
                else {
                    # This object cannot just be re-classified into a subclass because the subclass joins to additional tables.
                    # We'll make a parallel iterator for each subclass we encounter.
                    
                    # Note that we let the calling db-based iterator do that, so that if multiple objects on the row need 
                    # sub-classing, we do them all at once.
                    
                    # Decrement all of the param_keys it is using.
                    if ($loading_base_object) {
                        $loading_info = $dsx->_get_object_loading_info($pending_db_object);
                        $loading_info = $dsx->_reclassify_object_loading_info_for_new_class($loading_info,$subclass_name);
                    }
                    
                    #$pending_db_object->unload;
                    delete $UR::Context::all_objects_loaded->{$class}->{$pending_db_object_id};

                    if ($loading_base_object) {
                        $dsx->_record_that_loading_has_occurred($loading_info);
                    }
                    
                    # NOTE: we're returning a class name instead of an object
                    # this tells the caller to re-do the entire row using a subclass to get the real data.
                    # Hack?  Probably so...
                    return $subclass_name;
                }
                
                # the object may no longer match the rule after subclassifying...
                if ($loading_base_object and not $rule->evaluate($pending_db_object)) {
                    #print "Object does not match rule!" . Dumper($pending_db_object,[$rule->params_list]) . "\n";
                    #$DB::single = 1;
                    #$rule->evaluate($pending_db_object);
                    #$DB::single = 1;
                    #$rule->evaluate($pending_db_object);
                    return;
                    #$pending_db_object = undef;
                    #redo;
                }
            } # end of sub-classification code

            # Signal that the object has been loaded
            # NOTE: until this is done indexes cannot be used to look-up an object
            #$pending_db_object->__signal_change__('load_external');
            $pending_db_object->__signal_change__('load');
        
            #$DB::single = 1;
            if (
                $loading_base_object
                and
                $needs_further_boolexpr_evaluation_after_loading 
                and 
                not $rule->evaluate($pending_db_object)
            ) {
                return;
                #$pending_db_object = undef;
                #redo;
            }
        } # end handling newly loaded objects
        
        # If the rule had hints, mark that we loaded those things too, in all_params_loaded
        if (keys(%rule_hints)) {
            #$DB::single=1;
            foreach my $hint ( keys(%rule_hints) ) {
                #my @other_objs = UR::Context->get_current->infer_property_value_from_rule($hint, $rule);
                foreach my $hint_data ( @{ $rule_hints{$hint}} ) {
                    my @values = map { $pending_db_object->$_ } @{$hint_data->[0]}; # source property names
                    my $rule_tmpl = $hint_data->[1];
                    my $related_obj_rule = $rule_tmpl->get_rule_for_values(@values);
                    $UR::Context::all_params_loaded->{$rule_tmpl->subject_class_name}->{$related_obj_rule->id} = undef;
                    $all_params_loaded_items->{$rule_tmpl->subject_class_name}->{$related_obj_rule->id}++;
                 }
            }
        }

        # When there is recursion in the query, we record data from each 
        # recursive "level" as though the query was done individually.
        if ($recursion_desc and $loading_base_object) {
            # if we got a row from a query, the object must have
            # a db_committed or db_saved_committed                                
            my $dbc = $pending_db_object->{db_committed} || $pending_db_object->{db_saved_uncommitted};
            die 'No save info found in recursive data?' unless defined $dbc;
            
            my $value_by_which_this_object_is_loaded_via_recursion = $dbc->{$recurse_property_on_this_row};
            my $value_referencing_other_object = $dbc->{$recurse_property_referencing_other_rows};
            unless ($recurse_property_value_found{$value_referencing_other_object}) {
                # This row points to another row which will be grabbed because the query is hierarchical.
                # Log the smaller query which would get the hierarchically linked data directly as though it happened directly.
                $recurse_property_value_found{$value_referencing_other_object} = 1;
                # note that the direct query need not be done again
                #my $equiv_params = $class->define_boolexpr($recurse_property_on_this_row => $value_referencing_other_object);
                my $equiv_params = UR::BoolExpr->resolve(
                                       $class,
                                       $recurse_property_on_this_row => $value_referencing_other_object,
                                   );
                my $equiv_param_key = $equiv_params->normalize->id;                
                
                # note that the recursive query need not be done again
                #my $equiv_params2 = $class->define_boolexpr($recurse_property_on_this_row => $value_referencing_other_object, -recurse => $recursion_desc);
                my $equiv_params2 = UR::BoolExpr->resolve(
                                        $class,
                                        $recurse_property_on_this_row => $value_referencing_other_object,
                                        -recurse => $recursion_desc,
                                     );
                my $equiv_param_key2 = $equiv_params2->normalize->id;
                
                # For any of the hierarchically related data which is already loaded, 
                # note on those objects that they are part of that query.  These may have loaded earlier in this
                # query, or in a previous query.  Anything NOT already loaded will be hit later by the if-block below.
                my @subset_loaded = $class->is_loaded($recurse_property_on_this_row => $value_referencing_other_object);
                $UR::Context::all_params_loaded->{$class}{$equiv_param_key} = undef;
                $UR::Context::all_params_loaded->{$class}{$equiv_param_key2} = undef;
                $all_params_loaded_items->{$class}{$equiv_param_key} = scalar(@subset_loaded);
                $all_params_loaded_items->{$class}{$equiv_param_key2} = scalar(@subset_loaded);
                for my $pending_db_object (@subset_loaded) {
                    $pending_db_object->{load}->{param_key}{$class}{$equiv_param_key}++;
                    $pending_db_object->{load}->{param_key}{$class}{$equiv_param_key2}++;
                }
            }
           
            # NOTE: if it were possible to use undef values in a connect-by, this could be a problem
            # however, connect by in UR is always COL = COL, which would always fail on NULLs.
            if (defined($value_by_which_this_object_is_loaded_via_recursion) and $recurse_property_value_found{$value_by_which_this_object_is_loaded_via_recursion}) {
                # This row was expected because some other row in the hierarchical query referenced it.
                # Up the object count, and note on the object that it is a result of this query.
                #my $equiv_params = $class->define_boolexpr($recurse_property_on_this_row => $value_by_which_this_object_is_loaded_via_recursion);
                my $equiv_params = UR::BoolExpr->resolve(
                                       $class,
                                       $recurse_property_on_this_row => $value_by_which_this_object_is_loaded_via_recursion,
                                    );
                my $equiv_param_key = $equiv_params->normalize->id;
                
                # note that the recursive query need not be done again
                #my $equiv_params2 = $class->define_boolexpr($recurse_property_on_this_row => $value_by_which_this_object_is_loaded_via_recursion, -recurse => $recursion_desc);
                my $equiv_params2 = UR::BoolExpr->resolve(
                                        $class,
                                        $recurse_property_on_this_row => $value_by_which_this_object_is_loaded_via_recursion,
                                        -recurse => $recursion_desc
                                     );
                my $equiv_param_key2 = $equiv_params2->normalize->id;
                
                $UR::Context::all_params_loaded->{$class}{$equiv_param_key} = undef;
                $UR::Context::all_params_loaded->{$class}{$equiv_param_key2} = undef;
                $all_params_loaded_items->{$class}{$equiv_param_key}++;
                $all_params_loaded_items->{$class}{$equiv_param_key2}++;
                $pending_db_object->{load}->{param_key}{$class}{$equiv_param_key}++;
                $pending_db_object->{load}->{param_key}{$class}{$equiv_param_key2}++;
            }
        } # end of handling recursion
            
        return $pending_db_object;
        
    }; # end of per-class object fabricator
    Sub::Name::subname('UR::Context::__object_fabricator(closure)__', $object_fabricator);

    # remember all the changes to $UR::Context::all_params_loaded that should be made.
    # This fixes the problem where you create an iterator for a query, read back some of
    # the items, but not all, then later make the same query.  The old behavior made
    # entries in all_params_loaded as objects got loaded from the DB, so that at the time
    # the second query is made, UR::Context::_cache_is_complete_for_class_and_normalized_rule()
    # sees there are entries in all_params_loaded, and so reports yes, the cache is complete,
    # and the second query only returns the objects that were loaded during the first query.
    #
    # The new behavior builds up changes to be made to all_params_loaded, and someone
    # needs to call $object_fabricator->finalize() to apply these changes
    bless $object_fabricator, 'UR::Context::object_fabricator_tracker';
    $UR::Context::object_fabricators->{$object_fabricator} = $all_params_loaded_items;
    
    return $object_fabricator;
}

sub UR::Context::object_fabricator_tracker::finalize {
    my $self = shift;

    my $this_all_params_loaded = delete $UR::Context::object_fabricators->{$self};

    foreach my $class ( keys %$this_all_params_loaded ) {
        while(1) {
            my($rule_id,$val) = each %{$this_all_params_loaded->{$class}};
            last unless defined $rule_id;
            next unless exists $UR::Context::all_params_loaded->{$class}->{$rule_id};  # Has unload() removed this one earlier?
            $UR::Context::all_params_loaded->{$class}->{$rule_id} += $val; 
        }
    }
}
sub UR::Context::object_fabricator_tracker::DESTROY {
    my $self = shift;
    # Don't apply the changes.  Maybe the importer closure just went out of scope before
    # it read all the data
    my $this_all_params_loaded = delete $UR::Context::object_fabricators->{$self};
    if ($this_all_params_loaded) {
        # finalize wasn't called on this iterator; maybe the importer closure went out
        # of scope before it read all the data.
        # Conditionally apply the changes from the local all_params_loaded.  If the Context's
        # all_params_loaded is defined, then another query has successfully run to
        # completion, and we should add our data to it.  Otherwise, we're the only query like
        # this and all_params_loaded should be cleaned out
        foreach my $class ( keys %$this_all_params_loaded ) {
            while(1) {
                my($rule_id, $val) = each %{$this_all_params_loaded->{$class}};
                last unless $rule_id;
                if (defined $UR::Context::all_params_loaded->{$class}->{$rule_id}) {
                    $UR::Context::all_params_loaded->{$class}->{$rule_id} += $val;
                } else {
                    delete $UR::Context::all_params_loaded->{$class}->{$rule_id};
                }
            }
        }
    }
}


sub _get_objects_for_class_and_sql {
    # this is a depracated back-door to get objects with raw sql
    # only use it if you know what you're doing
    my ($self, $class, $sql) = @_;
    my $meta = $class->__meta__;        
    #my $ds = $self->resolve_data_sources_for_class_meta_and_rule($meta,$class->define_boolexpr());    
    my $ds = $self->resolve_data_sources_for_class_meta_and_rule($meta,UR::BoolExpr->resolve($class));
    my @ids = $ds->_resolve_ids_from_class_name_and_sql($class,$sql);
    return unless @ids;

    my $rule = UR::BoolExpr->resolve_normalized($class,id => \@ids);    
    
    return $self->get_objects_for_class_and_rule($class,$rule);
}

sub _cache_is_complete_for_class_and_normalized_rule {
    my ($self,$class,$normalized_rule) = @_;

    # TODO: convert this to use the rule object instead of going back to the legacy hash format

    my ($id,$params,@objects,$cache_is_complete);
    $params = $normalized_rule->legacy_params_hash;
    $id = $params->{id};

    # Determine ahead of time whether we believe the object MUST be loaded if it exists.
    # If this is true, we will shortcut out of any action which loads or prepares for loading.

    # Try to resolve without loading in cases where we are sure
    # that doing so will return the complete results.
    
    my $id_only = $params->{_id_only};
    $id_only = undef if ref($id) and ref($id) eq 'HASH';
    if ($id_only) {
        # _id_only means that only id parameters were passed in.
        # Either a single id or an arrayref of ids.
        # Try to pull objects from the cache in either case
        if (ref $id) {
            # arrayref id
            
            # we check the immediate class and all derived
            # classes for any of the ids in the set.
            @objects =
                grep { $_ }
                map { @$_{@$id} }
                map { $all_objects_loaded->{$_} }
                ($class, $class->subclasses_loaded);

            # see if we found all of the requested objects
            if (@objects == @$id) {
                # we found them all
                # return them all
                $cache_is_complete = 1;
            }
            else {
                # Ideally we'd filter out the ones we found,
                # but that gets complicated.
                # For now, we do it the slow way for partial matches
                @objects = ();
            }
        }
        else {
            # scalar id

            # Check for objects already loaded.
            no warnings;
            if (exists $all_objects_loaded->{$class}->{$id}) {
                $cache_is_complete = 1;
                @objects =
                    grep { $_ }
                    $all_objects_loaded->{$class}->{$id};
            }
            else {
                # we already checked the immediate class,
                # so just check derived classes
                @objects =
                    grep { $_ }
                    map { $all_objects_loaded->{$_}->{$id} }
                    $class->subclasses_loaded;
                if (@objects) {
                    $cache_is_complete = 1;
                }
            }
        }
    }
    elsif ($params->{_unique}) {
        # _unique means that this set of params could never
        # result in more than 1 object.  
        
        # See if the 1 is in the cache
        # If not we have to load
        
        @objects = $self->_get_objects_for_class_and_rule_from_cache($class,$normalized_rule);
        if (@objects) {
            $cache_is_complete = 1;
        }        
    }
    
    if ($cache_is_complete) {
        # if the $cache_is_comlete, the $cached list DEFINITELY represents all objects we need to return        
        # we know that loading is NOT necessary because what we've found cached must be the entire set
    
        # Because we happen to have that set, we return it in addition to the boolean flag
        return wantarray ? (1, \@objects) : ();
    }
    
    # We need to do more checking to see if loading is necessary
    # Either the parameters were non-unique, or they were unique
    # and we didn't find the object checking the cache.

    # See if we need to do a load():

    my $param_key = $params->{_param_key};
    my $loading_is_in_progress_on_another_iterator = 
            grep { exists $params->{_param_key}
                   and
                   exists $_->{$class}
                   and 
                   exists $_->{$class}->{$param_key}
                 }
            values %$UR::Context::object_fabricators;

    return 0 if $loading_is_in_progress_on_another_iterator;

    my $loading_was_done_before_with_these_params =
            # complex (non-single-id) params
            exists($params->{_param_key}) 
            && (
                # exact match to previous attempt
                exists ($UR::Context::all_params_loaded->{$class}->{$param_key})
                ||
                # this is a subset of a previous attempt
                ($self->_loading_was_done_before_with_a_superset_of_this_params_hashref($class,$params))
            );
    
    my $object_is_loaded_or_non_existent =
        $loading_was_done_before_with_these_params
        || $class->all_objects_are_loaded;
    
    if ($object_is_loaded_or_non_existent) {
        # These same non-unique parameters were used to load previously,
        # or we loaded everything at some point.
        # No load necessary.
        return 1;
    }
    else {
        # Load according to params
        return;
    }
} # done setting $load, and possibly filling $cached/$cache_is_complete as a side-effect


sub all_objects_loaded  {
    my $self = shift;
    my $class = $_[0];
    return(
        grep {$_}
        map { values %{ $UR::Context::all_objects_loaded->{$_} } } 
        $class, $class->subclasses_loaded
    );  
}

sub all_objects_loaded_unsubclassed  {
    my $self = shift;
    my $class = $_[0];
    return (grep {$_} values %{ $UR::Context::all_objects_loaded->{$class} } );
}


sub _get_objects_for_class_and_rule_from_cache {
    # Get all objects which are loaded in the application which match
    # the specified parameters.
    my ($self, $class, $rule) = @_;
    my ($template,@values) = $rule->template_and_values;
    
    #my @param_list = $rule->params_list;
    #print "CACHE-GET: $class @param_list\n";
    
    my $strategy = $rule->{_context_query_strategy};    
    unless ($strategy) {
        if ($rule->num_values == 0) {
            $strategy = $rule->{_context_query_strategy} = "all";
        }
        elsif ($rule->is_id_only) {
            $strategy = $rule->{_context_query_strategy} = "id";
        }        
        else {
            $strategy = $rule->{_context_query_strategy} = "index";
        }
    }
    
    my @results = eval {
    
        if ($strategy eq "all") {
            return $self->all_objects_loaded($class);
        }
        elsif ($strategy eq "id") {
            my $id = $rule->value_for_id();
            
            unless (defined $id) {
                $DB::single = 1;
                $id = $rule->value_for_id();
            }
            
            # Try to get the object(s) from this class directly with the ID.
            # Note that the code below is longer than it needs to be, but
            # is written to run quickly by resolving the most common cases
            # first, and gathering data only if and when it must.
    
            my @matches;
            if (ref($id) eq 'ARRAY') {
                # The $id is an arrayref.  Get all of the set.
                @matches = grep { $_ } map { @$_{@$id} } map { $all_objects_loaded->{$_} } ($class);
                
                # We're done if the number found matches the number of ID values.
                return @matches if @matches == @$id;
            }
            else {
                # The $id is a normal scalar.
                if (not defined $id) {
                    Carp::cluck("Undefined id passed as params!");
                }
                my $match;
                # FIXME This is a performance optimization for class metadata to avoid the search through
                # @subclasses_loaded a few lines further down.  When 100s of classes are loaded it gets
                # a bit slow.  Maybe UR::Object::Type should override get() instad and put it there?
                if (! $UR::Object::Type::bootstrapping and $class eq 'UR::Object::Type') {
                    my $meta_class_name = $id . '::Type';
                    $match = $all_objects_loaded->{$meta_class_name}->{$id}
                             ||
                             $all_objects_loaded->{'UR::Object::Type'}->{$id};
                    if ($match) {
                        return $match;
                    } else {
                        return;
                    }
                }   

                $match = $all_objects_loaded->{$class}->{$id};
    
                # We're done if we found anything.  If not we keep checking.
                return $match if $match;
            }
    
            # Try to get the object(s) from this class's subclasses.
            # We may be adding to matches made above is we used an arrayref
            # and the results are incomplete.
    
            my @subclasses_loaded = $class->subclasses_loaded;
            return @matches unless @subclasses_loaded;
    
            if (ref($id) eq 'ARRAY') {
                # The $id is an arrayref.  Get all of the set and add it to anything found above.
                push @matches,
                    grep { $_  }
                    map { @$_{@$id} }
                    map { $all_objects_loaded->{$_} }
                    @subclasses_loaded;    
            }
            else {
                # The $id is a normal scalar, but we didn't find it above.
                # Try each subclass, exiting if we find anything.
                for (@subclasses_loaded) {
                    my $match = $all_objects_loaded->{$_}->{$id};
                    return $match if $match;
                }
            }
            
            # Since an ID was specified, and we've scanned the core hash every way possible,
            # we're done.  Return nothing if necessary.
            return @matches;
        }
        elsif ($strategy eq "index") {
            # FIXME - optimize by using the rule (template?)'s param names directly to get the
            # index id instead of re-figuring it out each time

            my $class_meta = UR::Object::Type->get($rule->subject_class_name);
            my %params = $rule->params_list;
            my $should_evaluate_later;
            for my $key (keys %params) {
                delete $params{$key} if substr($key,0,1) eq '-' or substr($key,0,1) eq '_';
                my $prop_meta = $class_meta->property_meta_for_name($key);
                if ($prop_meta && $prop_meta->is_many) {
                    # These indexes perform poorly in the general case if we try to index
                    # the is_many properties.  Instead, strip them out from the basic param
                    # list, and evaluate the superset of indexed objects through the rule
                    $should_evaluate_later = 1;
                    delete $params{$key};
                }
            }
            
            my @properties = sort keys %params;
            my @values = map { $params{$_} } @properties;
            
            unless (@properties == @values) {
                Carp::confess();
            }
            
            # find or create the index
            my $index_id = UR::Object::Index->__meta__->resolve_composite_id_from_ordered_values($class,join(",",@properties));
            #my $index_id2 = $rule->index_id;
            #unless ($index_id eq $index_id2) {
            #    Carp::confess("Index ids don't match: $index_id, $index_id2\n");
            #}
            my $index = $all_objects_loaded->{'UR::Object::Index'}{$index_id};
            $index ||= UR::Object::Index->create($index_id);
            

            # add the indexed objects to the results list
            
            
            if ($UR::Debug::verify_indexes) {
                my @matches = $index->get_objects_matching(@values);        
                @matches = sort @matches;
                my @matches2 = sort grep { $rule->evaluate($_) } $self->all_objects_loaded($class);
                unless ("@matches" eq "@matches2") {
                    print "@matches\n";
                    print "@matches2\n";
                    $DB::single = 1;
                    #Carp::cluck("Mismatch!");
                    my @matches3 = $index->get_objects_matching(@values);
                    my @matches4 = $index->get_objects_matching(@values);                
                    return @matches2; 
                }
                return @matches;
            }
            
            if ($should_evaluate_later) {
                return grep { $rule->evaluate($_) } $index->get_objects_matching(@values);
            } else {
                return $index->get_objects_matching(@values);
            }
        }
    };
        
    # Handle passing-through any exceptions.
    die $@ if $@;

    if (my $recurse = $template->recursion_desc) {        
        my ($this,$prior) = @$recurse;
        my @values = map { $_->$prior } @results;
        if (@values) {
            # We do get here, so that adjustments to intermediate foreign keys
            # in the cache will result in a new query at the correct point,
            # and not result in missing data.
            #push @results, $class->get($this => \@values, -recurse => $recurse);
            push @results, map { $class->get($this => $_, -recurse => $recurse) } @values;
        }
    }
    
    if (@results > 1) {
        my $sorter = $template->sorter;
        @results = sort $sorter @results;
    }

    if (my $group_by = $template->group_by) {
        # return sets instead of the actual objects
        @results = _group_objects($template,\@values,$group_by,\@results);
    }

    # Return in the standard way.
    return @results if (wantarray);
    Carp::confess("Multiple matches for $class @_!") if (@results > 1);
    return $results[0];
}

sub _group_objects {
    my ($template,$values,$group_by,$objects)  = @_;
    my $sub_template = $template;
    for my $property (@$group_by) {
        $sub_template = $sub_template->add_filter($property);
    }
    my $set_class = $template->subject_class_name . '::Set';
    my @groups;
    my %seen;
    for my $result (@$objects) {
        my @extra_values = map { $result->$_ } @$group_by;
        my $bx = $sub_template->get_rule_for_values(@$values,@extra_values);
        next if $seen{$bx};
        $seen{$bx} = 1;
        my $group = $set_class->get($bx->id); 
        push @groups, $group;
    }
    return @groups;
}

sub _loading_was_done_before_with_a_superset_of_this_params_hashref  {
    my ($self,$class,$input_params) = @_;

    my @params_property_names =
        grep {
            $_ ne "id"
                and not (substr($_,0,1) eq "_")
                and not (substr($_,0,1) eq "-")
            }
    keys %$input_params;

    for my $try_class ( $class, $class->inheritance ) {
        # more than one property, see if individual checks have been done for any of these...
        my $try_class_meta = $try_class->__meta__;
        next unless $try_class_meta;

        my @param_combinations = $self->_get_all_subsets_of_params(
                                     grep { $try_class_meta->property_meta_for_name($_) }
                                          @params_property_names
                                 );
        # get rid of first (empty) entry.  For no params, this would
        # have been caught by $all_objects_are_loaded
        shift @param_combinations; 
        foreach my $params ( @param_combinations ) {
            my %get_hash = map { $_ => $input_params->{$_} } @$params;
            #my $key = $try_class->define_boolexpr(%get_hash)->id;
            my $rule = UR::BoolExpr->resolve_normalized($try_class, %get_hash);
            my $key = $rule->id;
            if (defined($key) and exists $all_params_loaded->{$try_class}->{$key} and defined $all_params_loaded->{$try_class}->{$key}) {

                $all_params_loaded->{$try_class}->{$input_params->{_param_key}} = 1;
                my $new_key = $input_params->{_param_key};
                for my $obj ($self->all_objects_loaded($try_class)) {
                    my $load_data = $obj->{load};
                    next unless $load_data;
                    my $param_key_data = $load_data->{param_key};
                    next unless $param_key_data;
                    my $class_data = $param_key_data->{$try_class};
                    next unless $class_data;
                    $class_data->{$new_key}++;
                }
                return 1;
            }
        }
        # No sense looking further up the inheritance
        # FIXME UR::ModuleBase is in the inheritance list, you can't call __meta__() on it
        # and I'm having trouble getting a UR class object defined for it...
        last if ($try_class eq 'UR::Object');
    }
    return;
}


sub _forget_loading_was_done_with_class_and_rule {
    my($self,$class_name, $rule) = @_;

    delete $all_params_loaded->{$class_name}->{$rule->id};
}

# Given a list of values, returns a list of lists containing all subsets of
# the input list, including the original list and the empty list
sub _get_all_subsets_of_params {
    my $self = shift;

    return [] unless @_;
    my $first = shift;
    my @rest = $self->_get_all_subsets_of_params(@_);
    return @rest, map { [$first, @$_ ] } @rest;
}


# all of these delegate to the current context...

sub has_changes {
    return shift->get_current->has_changes(@_);
}

sub get_time_ymdhms {
    my $self = shift;

    return;
    
    # TODO: go through the DBs and find one with the ability to do systime.
    # Failing that, return the local time.
    
    # Old UR::Time logic:
    
    return unless ($self->get_data_source->has_default_dbh);

    $DB::single = 1;
 
    # synchronize with the database and store the difference 
    # get database time (query is Oracle specific)
    my $date_query = q(select sysdate from dual);
    my ($db_time); # = ->dbh->selectrow_array($date_query);

    # parse database time
    my @db_now = strptime($db_time);
    if (@db_now)
    {
        # correct month and year
        ++$db_now[4];
        $db_now[5] += 1900;
        # reverse order
        @db_now = reverse((@db_now)[0 .. 5]);
    }
    else
    {
        $self->warning_message("failed to parse $db_time with strptime");
        # fall back to old method
        @db_now = split(m/[-\s:]/, $db_time);
    }
    return @db_now;
}

sub commit {
    my $self = shift;

    unless ($self) {
        warn 'UR::Context::commit() called as a function, not a method.  Assumming commit on current context';
        $self = UR::Context->current();
    }
    $self->__signal_change__('precommit');

    unless ($self->_sync_databases) {
        $self->__signal_change__('commit',0);
        return;
    }
    unless ($self->_commit_databases) {
        $self->__signal_change__('commit',0);
        die "Application failure during commit!";
    }
    $self->__signal_change__('commit',1);

    foreach ( $self->all_objects_loaded('UR::Object') ) {
        delete $_->{'_change_count'};
    }

    return 1;
}

sub rollback {
    my $self = shift;

    unless ($self) {
        warn 'UR::Context::rollback() called as a function, not a method.  Assumming rollback on current context';
        $self = UR::Context->current();
    }
    $self->__signal_change__('prerollback');

    unless ($self->_reverse_all_changes) {
        $self->__signal_change__('rollback', 0);
        die "Application failure during reverse_all_changes?!";
    }
    unless ($self->_rollback_databases) {
        $self->__signal_change__('rollback', 0);
        die "Application failure during rollback!";
    }
    $self->__signal_change__('rollback', 1);
    return 1;
}

sub _tmp_self {
    my $self = shift;
    if (ref($self)) {
        return ($self,ref($self));
    }
    else {
        return ($UR::Context::current, $self);
    }
}

sub clear_cache {
    my ($self,$class) = _tmp_self(shift @_);
    my %args = @_;

    # dont unload any of the infrastructional classes, or any classes
    # the user requested to be saved
    my %local_dont_unload;
    if ($args{'dont_unload'}) {
        for my $class_name (@{$args{'dont_unload'}}) {
            $local_dont_unload{$class_name} = 1;
            for my $subclass_name ($class_name->subclasses_loaded) {
                $local_dont_unload{$subclass_name} = 1;
            }
        }
    }

    for my $class_name (UR::Object->subclasses_loaded) {

        # Once transactions are fully implemented, the command params will sit
        # beneath the regular transaction, so we won't need this.  For now,
        # we need a work-around.
        next if $class_name eq "UR::Command::Param";
        next if $class_name->isa('UR::Singleton');
        
        my $class_obj = $class_name->__meta__;
        #if ($class_obj->data_source and $class_obj->is_transactional) {
        #    # normal
        #}
        #elsif (!$class_obj->data_source and !$class_obj->is_transactional) {
        #    # expected
        #}
        #elsif ($class_obj->data_source and !$class_obj->is_transactional) {
        #    Carp::confess("!!!!!data source on non-transactional class $class_name?");
        #}
        #elsif (!$class_obj->data_source and $class_obj->is_transactional) {
        #    # okay
        #}

        next unless $class_obj->is_uncachable;
        next if $class_obj->is_meta_meta;
        next unless $class_obj->is_transactional;

        next if ($local_dont_unload{$class_name} ||
                 grep { $class_name->isa($_) } @{$args{'dont_unload'}});

        next if $class_obj->is_meta;

        next if not defined $class_obj->data_source;

        for my $obj ($self->all_objects_loaded_unsubclassed($class_name)) {
            # Check the type against %local_dont_unload again, because all_objects_loaded()
            # will return child class objects, as well as the class you asked for.  For example,
            # GSC::DNA->a_o_l() will also return GSC::ReadExp objects, and the user may have wanted
            # to save those.  We also check whether the $obj type isa one of the requested classes
            # because, for example, GSC::Sequence->a_o_l returns GSC::ReadExp types, and the user
            # may have wanted to save all GSC::DNAs
            my $obj_type = ref $obj;
            next if ($local_dont_unload{$obj_type} ||
                     grep {$obj_type->isa($_) } @{$args{'dont_unload'}});
            $obj->unload;
        }
        my @obj = grep { defined($_) } values %{ $UR::Context::all_objects_loaded->{$class_name} };
        if (@obj) {
            $class->warning_message("Skipped unload of $class_name objects during clear_cache: "
                . join(",",map { $_->id } @obj )
                . "\n"
            );
            if (my @changed = grep { $_->__changes__ } @obj) {
                require YAML;
                $class->error_message(
                    "The following objects have changes:\n"
                    . Data::Dumper::Dumper(\@changed)
                    . "The clear_cache method cannot be called with unsaved changes on objects.\n"
                    . "Use reverse_all_changes() first to really undo everything, then clear_cache(),"
                    . " or call sync_database() and clear_cache() if you want to just lighten memory but keep your changes.\n"
                    . "Clearing the cache with active changes will be supported after we're sure all code like this is gone. :)\n"                    
                );
                exit 1;
            }
        }
        delete $UR::Context::all_objects_loaded->{$class_name};
        delete $UR::Context::all_objects_are_loaded->{$class_name};
        delete $UR::Context::all_params_loaded->{$class_name};
    }
    1;
}


our $IS_SYNCING_DATABASE = 0;
sub _sync_databases {
    my $self = shift;
    my %params = @_;

    # Glue App::DB->sync_database with UR::Context->_sync_databases()
    # and avoid endless recursion.
    # FIXME Remove this when we're totally off of the old API
    # You'll also want to remove all the gotos from this function and uncomment
    # the returns
    return 1 if $IS_SYNCING_DATABASE;
    $IS_SYNCING_DATABASE = 1;
    if ($App::DB::{'sync_database'}) {
        unless (App::DB->sync_database() ) {
            $IS_SYNCING_DATABASE = 0;
            $self->error_message(App::DB->error_message());
            return;
        }
    }
    $IS_SYNCING_DATABASE = 0;  # This should be far down enough to avoid recursion, right?
 
    my @o = grep { ref($_) eq 'UR::DeletedRef' } $self->all_objects_loaded('UR::Object');
    if (@o) {
        print Data::Dumper::Dumper(\@o);
        Carp::confess();
    }

    # Determine what has changed.
    my @changed_objects = (
        $self->all_objects_loaded('UR::Object::Ghost'),
        grep { $_->__changes__ } $self->all_objects_loaded('UR::Object')
        #UR::Util->mapreduce_grep(sub { $_[0]->__changes__ },$self->all_objects_loaded('UR::Object'))
    );

    return 1 unless (@changed_objects);

    # Ensure validity.
    # This is primarily to catch custom validity logic in class overrides.
    my @invalid = grep { $_->__errors__ } @changed_objects;
    #my @invalid = UR::Util->mapreduce_grep(sub { $_[0]->__errors__}, @changed_objects);
    if (@invalid) {
        # Create a helpful error message for the developer.
        $self->error_message('Invalid data for save!');
        my @msg;
        for my $obj (@invalid)
        {
            no warnings;
            my $msg = $obj->class . " identified by " . $obj->__display_name__ . " has problems on\n";
            my @problems = $obj->__errors__;
            foreach my $error ( @problems ) {
                my @property_names = $error->properties;
                my $desc = $error->desc;
                my $prop_noun = scalar(@property_names) > 1 ? 'properties' : 'property';
                $msg .= "    $prop_noun " . join(', ', map { "'$_'" } @property_names) . ": $desc\n";
            }
            $msg .= "    Current state:\n" . Data::Dumper::Dumper($obj);
            $self->error_message($msg);
        }
        goto PROBLEM_SAVING;
        #return;
    }

    # group changed objects by data source
    my %ds_objects;
    for my $obj (@changed_objects) {
        my $data_source = $self->resolve_data_source_for_object($obj);
        next unless $data_source;
        my $data_source_id = $data_source->id;
        $ds_objects{$data_source_id} ||= { 'ds_obj' => $data_source, 'changed_objects' => []};
        push @{ $ds_objects{$data_source_id}->{'changed_objects'} }, $obj;
    }

    my @ds_in_order = 
        sort {
            ($ds_objects{$a}->{'ds_obj'}->can_savepoint <=> $ds_objects{$b}->{'ds_obj'}->can_savepoint)
            || 
            ($ds_objects{$a}->{'ds_obj'}->class cmp $ds_objects{$b}->{'ds_obj'}->class)
        }
        keys %ds_objects;

    # save on each in succession
    my @done;
    my $rollback_on_non_savepoint_handle;
    for my $data_source_id (@ds_in_order) {
        my $obj_list = $ds_objects{$data_source_id}->{'changed_objects'};
        my $data_source = $ds_objects{$data_source_id}->{'ds_obj'};
        my $result = $data_source->_sync_database(
            %params,
            changed_objects => $obj_list,
        );
        if ($result) {
            push @done, $data_source;
            next;
        }
        else {
            $self->error_message(
                "Failed to sync data source: $data_source_id: "
                . $data_source->error_message
            );
            for my $prev_data_source (@done) {
                $prev_data_source->_reverse_sync_database;
            }
            goto PROBLEM_SAVING;
            #return;
        }
    }
    
    return 1;

    PROBLEM_SAVING:
    if ($App::DB::{'rollback'}) {
        App::DB->rollback();
    }
    return;
}

sub _reverse_all_changes {
    my $self = shift;
    my $class;
    if (ref($self)) {
        $class = ref($self);
    }
    else {
        $class = $self;
        $self = $UR::Context::current;
    }

    @UR::Context::Transaction::open_transaction_stack = ();
    @UR::Context::Transaction::change_log = ();
    $UR::Context::Transaction::log_all_changes = 0;
    $UR::Context::current = $UR::Context::process;
    
    # aggregate the objects to be deleted
    # this prevents cirucularity, since some objects 
    # can seem re-reversible (like ghosts)
    my %_delete_objects;
    my @all_subclasses_loaded = sort UR::Object->subclasses_loaded;
    for my $class_name (@all_subclasses_loaded) { 
        next unless $class_name->can('__meta__');
        
        my @objects_this_class = $self->all_objects_loaded_unsubclassed($class_name);
        next unless @objects_this_class;
        
        $_delete_objects{$class_name} = \@objects_this_class;
    }
    
    # do the reverses
    for my $class_name (keys %_delete_objects) {
        my $co = $class_name->__meta__;
        next unless $co->is_transactional;

        my $objects_this_class = $_delete_objects{$class_name};

        if ($class_name->isa("UR::Object::Ghost")) {
            # ghose placeholder for a deleted object
            for my $object (@$objects_this_class) {
                # revive ghost object
    
                my $ghost_copy = eval("no strict; no warnings; " . Data::Dumper::Dumper($object));
                if ($@) {
                    Carp::confess("Error re-constituting ghost object: $@");
                }
                my $new_object = $object->live_class->UR::Object::create(
                    %{ $ghost_copy->{db_committed} },                    
                );
                $new_object->{db_committed} = $ghost_copy->{db_committed};
                unless ($new_object) {
                    Carp::confess("Failed to re-constitute $object!");
                }
                next;
            }
        }       
        else {
            # non-ghost regular entity
            for my $object (@$objects_this_class) {
                # find property_names (that have columns)
                # todo: switch to check persist
                my %property_names =
                    map { $_->property_name => $_ }
                    grep { defined $_->column_name }
                    $co->all_property_metas
                ;
        
                # find columns which make up the primary key
                # convert to a hash where property => 1
                my @id_property_names = $co->all_id_property_names;
                my %id_props = map {($_, 1)} @id_property_names;
        
                
                my $saved = $object->{db_saved_uncommitted} || $object->{db_committed};
                
                if ($saved) {
                    # Existing object.  Undo all changes since last sync, 
                    # or since load occurred when there have been no syncs.
                    foreach my $property_name ( keys %property_names ) {
                        # only do this if the column is not part of the
                        # primary key
                        my $property_meta = $property_names{$property_name};
                        next if ($id_props{$property_name} ||
                                 $property_meta->is_delegated ||
                                 $property_meta->is_legacy_eav ||
                                 ! $property_meta->is_mutable ||
                                 $property_meta->is_transient);
                        $object->$property_name($saved->{$property_name});
                    }
                }
                else {
                    # Object not in database, get rid of it.
                    # Because we only go back to the last sync not (not last commit),
                    # this no longer has to worry about rolling back an uncommitted database save which may have happened.
                    UR::Object::delete($object);
                }

            } # next non-ghost object
        } 
    } # next class
    return 1;
}

our $IS_COMMITTING_DATABASE = 0;
sub _commit_databases {
    my $class = shift;

    # Glue App::DB->commit() with UR::Context->_commit_databases()
    # and avoid endless recursion.
    # FIXME Remove this when we're totally off of the old API
    return 1 if $IS_COMMITTING_DATABASE;
    $IS_COMMITTING_DATABASE = 1;
    if ($App::DB::{'commit'}) {
        unless (App::DB->commit() ) {
	    $IS_COMMITTING_DATABASE = 0;
            $class->error_message(App::DB->error_message());
            return;
        }
    }
    $IS_COMMITTING_DATABASE = 0;

    unless ($class->_for_each_data_source("commit")) {
        if ($class->error_message eq "PARTIAL commit") {
            die "FRAGMENTED DISTRIBUTED TRANSACTION\n"
                . Data::Dumper::Dumper($UR::Context::all_objects_loaded)
        }
        else {
            die "FAILED TO COMMIT!: " . $class->error_message;
        }
    }

    return 1;
}


our $IS_ROLLINGBACK_DATABASE = 0;
sub _rollback_databases {
    my $class = shift;

    # Glue App::DB->rollback() with UR::Context->_rollback_databases()
    # and avoid endless recursion.
    # FIXME Remove this when we're totally off of the old API
    return 1 if $IS_ROLLINGBACK_DATABASE;
    $IS_ROLLINGBACK_DATABASE = 1;
    if ($App::DB::{'rollback'}) {
        unless (App::DB->rollback()) {
            $IS_ROLLINGBACK_DATABASE = 0;
            $class->error_message(App::DB->error_message());
            return;
        }
    }
    $IS_ROLLINGBACK_DATABASE = 0;

    $class->_for_each_data_source("rollback")
        or die "FAILED TO ROLLBACK!: " . $class->error_message;
    return 1;
}

sub _disconnect_databases {
    my $class = shift;
    $class->_for_each_data_source("disconnect");
    return 1;
}    

sub _for_each_data_source {
    my($class,$method) = @_;

    my @ds = $UR::Context::current->all_objects_loaded('UR::DataSource');
    foreach my $ds ( @ds ) {
       unless ($ds->$method) {
           $class->error_message("$method failed on DataSource ",$ds->get_name);
           return; 
       }
    }
    return 1;
}

sub _get_committed_property_value {
    my $class = shift;
    my $object = shift;
    my $property_name = shift;

    if ($object->{'db_committed'}) {
        return $object->{'db_committed'}->{$property_name};
    } elsif ($object->{'db_saved_uncommitted'}) {
        return $object->{'db_saved_uncommitted'}->{$property_name};
    } else {
        return;
    }
}

sub _dump_change_snapshot {
    my $class = shift;
    my %params = @_;

    my @c = grep { $_->__changes__ } $UR::Context::current->all_objects_loadedi('UR::Object');

    my $fh;
    if (my $filename = $params{filename})
    {
        $fh = IO::File->new(">$filename");
        unless ($fh)
        {
            $class->error_message("Failed to open file $filename: $!");
            return;
        }
    }
    else
    {
        $fh = "STDOUT";
    }
    require YAML;
    $fh->print(YAML::Dump(\@c));
    $fh->close;
}

sub reload {
    my $self = shift;

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

    my ($rule, @extra) = UR::BoolExpr->resolve_normalized($class,@_);
    
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

## This is old, untested code that we may wany to resurrect at some point
#
#our $CORE_DUMP_VERSION = 1;
## Use Data::Dumper to save a representation of the object cache to a file.  Args are:
## filename => the name of the file to save to
## dumpall => boolean flagging whether to dump _everything_, or just the things
##            that would actually be loaded later in core_restore()
#
#sub _core_dump {
#    my $class = shift;
#    my %args = @_;
#
#    my $filename = $args{'filename'} || "/tmp/core." . UR::Context::Process->prog_name . ".$ENV{HOST}.$$";
#    my $dumpall = $args{'dumpall'};
#
#    my $fh = IO::File->new(">$filename");
#    if (!$fh) {
#      $class->error_message("Can't open dump file $filename for writing: $!");
#      return undef;
#    }
#
#    my $dumper;
#    if ($dumpall) {  # Go ahead and dump everything
#        $dumper = Data::Dumper->new([$CORE_DUMP_VERSION,
#                                     $UR::Context::all_objects_loaded,
#                                     $UR::Context::all_objects_are_loaded,
#                                     $UR::Context::all_params_loaded,
#                                     $UR::Context::all_change_subscriptions],
#                                    ['dump_version','all_objects_loaded','all_objects_are_loaded',
#                                     'all_params_loaded','all_change_subscriptions']);
#    } else {
#        my %DONT_UNLOAD =
#            map {
#                my $co = $_->__meta__;
#                if ($co and not $co->is_transactional) {
#                    ($_ => 1)
#                }
#                else {
#                    ()
#                }
#            }
#             $UR::Context::current->all_objects_loaded('UR::Object');
#
#        my %aol = map { ($_ => $UR::Context::all_objects_loaded->{$_}) }
#                     grep { ! $DONT_UNLOAD{$_} } keys %$UR::Context::all_objects_loaded;
#        my %aoal = map { ($_ => $UR::Context::all_objects_are_loaded->{$_}) }
#                      grep { ! $DONT_UNLOAD{$_} } keys %$UR::Context::all_objects_are_loaded;
#        my %apl = map { ($_ => $UR::Context::all_params_loaded->{$_}) }
#                      grep { ! $DONT_UNLOAD{$_} } keys %$UR::Context::all_params_loaded;
#        # don't dump $UR::Context::all_change_subscriptions
#        $dumper = Data::Dumper->new([$CORE_DUMP_VERSION,\%aol, \%aoal, \%apl],
#                                    ['dump_version','all_objects_loaded','all_objects_are_loaded',
#                                     'all_params_loaded']);
#
#    }
#
#    $dumper->Purity(1);   # For dumping self-referential data structures
#    $dumper->Sortkeys(1); # Makes quick and dirty file comparisons with sum/diff work correctly-ish
#
#    $fh->print($dumper->Dump() . "\n");
#
#    $fh->close;
#
#    return $filename;
#}
#
## Read a file previously generated with core_dump() and repopulate the object cache.  Args are:
## filename => name of the coredump file
## force => boolean flag whether to go ahead and attempt to load the file even if it thinks
##          there is a formatting problem
#sub _core_restore {
#    my $class = shift;
#    my %args = @_;
#    my $filename = $args{'filename'};
#    my $forcerestore = $args{'force'};
#
#    my $fh = IO::File->new("$filename");
#    if (!$fh) {
#        $class->error_message("Can't open dump file $filename for restoring: $!");
#        return undef;
#    }
#
#    my $code;
#    while (<$fh>) { $code .= $_ }
#
#    my($dump_version,$all_objects_loaded,$all_objects_are_loaded,$all_params_loaded,$all_change_subscriptions);
#    eval $code;
#
#    if ($@)
#    {
#        $class->error_message("Failed to restore core file state: $@");
#        return undef;
#    }
#    if ($dump_version != $CORE_DUMP_VERSION) {
#      $class->error_message("core file's version $dump_version differs from expected $CORE_DUMP_VERSION");
#      return 0 unless $forcerestore;
#    }
#
#    my %DONT_UNLOAD =
#        map {
#            my $co = $_->__meta__;
#            if ($co and not $co->is_transactional) {
#                ($_ => 1)
#            }
#            else {
#                ()
#            }
#        }
#        $UR::Context::current->all_objects_loaded('UR::Object');
#
#    # Go through the loaded all_objects_loaded, prune out the things that
#    # are in %DONT_UNLOAD
#    my %loaded_classes;
#    foreach ( keys %$all_objects_loaded ) {
#        next if ($DONT_UNLOAD{$_});
#        $UR::Context::all_objects_loaded->{$_} = $all_objects_loaded->{$_};
#        $loaded_classes{$_} = 1;
#
#    }
#    foreach ( keys %$all_objects_are_loaded ) {
#        next if ($DONT_UNLOAD{$_});
#        $UR::Context::all_objects_are_loaded->{$_} = $all_objects_are_loaded->{$_};
#        $loaded_classes{$_} = 1;
#    }
#    foreach ( keys %$all_params_loaded ) {
#        next if ($DONT_UNLOAD{$_});
#        $UR::Context::all_params_loaded->{$_} = $all_params_loaded->{$_};
#        $loaded_classes{$_} = 1;
#    }
#    # $UR::Context::all_change_subscriptions is basically a bunch of coderef
#    # callbacks that can't reliably be dumped anyway, so we skip it
#
#    # Now, get the classes to instantiate themselves
#    foreach ( keys %loaded_classes ) {
#        $_->class() unless m/::Ghost$/;
#    }
#
#    return 1;
#}

1;

=pod

=head1 NAME

UR::Context - Manage the current state of the application

=head1 SYNOPSIS

  use AppNamespace;

  my $obj = AppNamespace::SomeClass->get(id => 1234);
  $obj->some_property('I am changed');

  UR::Context->get_current->rollback; # some_property reverts to its original value

  $obj->other_property('Now, I am changed');

  UR::Context->commit; # other_property now permanently has that value


=head1 DESCRIPTION

The main application code will rarely interact with UR::Context objects
directly, except for the C<commit> and C<rollback> methods.  It manages
the mappings between an application's classes, object cache, and external
data sources.

=head1 SUBCLASSES

UR::Context is an abstract class.  When an application starts up, the system
creates a handful of Contexts that logically exist within one another:

=over 2

=item 1.
L<UR::Context::Root> - A context to represent all the data reachable in the
application's namespace.  It connects the application to external data
sources.

=item 2.
L<UR::Context::Process> - A context to represent the state of data within
the currently running application.  It handles the transfer of data to and
from the Root context, through the object cache, on behalf of the application
code.

=item 3.
L<UR::Context::Transaction> - A context to represent an in-memory transaction
as a diff of the object cache.  The Transaction keeps a list of changes to
objects and is able to revert those changes with C<rollback()>, or apply them
to the underlying context with C<commit()>.

=back

=head1 CONSTRUCTOR

=over 4

=item begin

  my $trans = UR::Context::Transaction->begin();

L<UR::Context::Transaction> instances are created through C<begin()>.  

=back

A L<UR::Context::Root> and L<UR::Context::Process> context will be created
for you when the application initializes.  Additional instances of these
classes are not usually instantiated.

=head1 METHODS

Most of the methods below can be called as either a class or object method
of UR::Context.  If called as a class method, they will operate on the current
context.

=over 4

=item get_current

  my $context = UR::Context::get_current();

Returns the UR::Context instance of whatever is the most currently created
Context.  Can be called as a class or object method.

=item get_objects_for_class_and_rule

  @objs = $context->get_objects_for_class_and_rule(
                        $class_name,
                        $boolexpr,
                        $should_load,
                        $should_return_iterator
                    );

This is the method that serves as the main entry point to the Context behind
the C<get()>, C<load()> and C<is_loaded()> methods of L<UR::Object>.  

C<$class_name> and C<$boolexpr> are required arguments, and specify the 
target class by name and the rule used to filter the objects the caller
is interested in.  

C<$should_load> is a flag indicating whether the Context should load objects
satisfying the rule from external data sources.  A true value means it should
always ask the relevent data sources, even if the Context believes the 
requested data is in the object cache,  A false but defined value means the
Context should not ask the data sources for new data, but only return what
is currently in the cache matching the rule.  The value C<undef> means the
Context should use its own judgement about asking the data sources for new
data, and will merge cached and external data as necessary to fulfill the
request.

C<$should_return_iterator> is a flag indicating whether this method should
return the objects directly as a list, or iterator function instead.  If
true, it returns a subref that returns one object each time it is called,
and undef after the last matching object:

  my $iter = $context->get_objects_for_class_and_rule(
                           'MyClass',
                           $rule,
                           undef,
                           1
                       );
  my @objs;
  while (my $obj = $iter->());
      push @objs, $obj;
  }

=item has_changes

  my $bool = $context->has_changes();

Returns true if any objects in the given Context's object cache (or the
current Context if called as a class method) have any changes that haven't
been saved to the underlying context.

=item commit

  UR::Context->commit();

Causes all objects with changes to save their changes back to the underlying
context.  If the current context is a L<UR::Context::Transaction>, then the
changes will be applied to whatever Context the transaction is a part of.
if the current context is a L<UR::Context::Process> context, then C<commit()>
pushes the changes to the underlying L<UR::Context::Root> context, meaning 
that those changes will be applied to the relevent data sources.

In the usual case, where no transactions are in play and all data sources
are RDBMS databases, calling C<commit()> will cause the program to begin
issuing SQL against the databases to update changed objects, insert rows
for newly created objects, and delete rows from deleted objects as part of
an SQL transaction.  If all the changes apply cleanly, it will do and SQL
C<commit>, or C<rollback> if not.

commit() returns true if all the changes have been safely transferred to the
underlying context, false if there were problems.

=item rollback

  UR::Context->rollback();

Causes all objects' changes for the current transaction to be reversed.
If the current context is a L<UR::Context::Transaction>, then the
transactional properties of those objects will be reverted to the values
they had when the transaction started.  Outside of a transaction, object
properties will be reverted to their values when they were loaded from the
underlying data source.  rollback() will also ask all the underlying
databases to rollback.

=item clear_cache

  UR::Context->clear_cache();

Asks the current context to remove all non-infrastructional data from its
object cache.  This method will fail and return false if any object has
changes.

=item resolve_data_source_for_object

  my $ds = $obj->resolve_data_source_for_object();

For the given C<$obj> object, return the L<UR::DataSource> instance that 
object was loaded from or would be saved to.  If objects of that class do
not have a data source, then it will return C<undef>.

=item resolve_data_sources_for_class_meta_and_rule

  my @ds = $context->resolve_data_sources_for_class_meta_and_rule($class_obj, $boolexpr);

For the given class metaobject and boolean expression (rule), return the list of
data sources that will need to be queried in order to return the objects
matching the rule.  In most cases, only one data source will be returned.

=item infer_property_value_from_rule

  my $value = $context->infer_property_value_from_rule($property_name, $boolexpr);

For the given boolean expression (rule), and a property name not mentioned in
the rule, but is a property of the class the rule is against, return the value
that property must logically have.

For example, if this object is the only TestClass object where C<foo> is
the value 'bar', it can infer that the TestClass property C<baz> must
have the value 'blah' in the current context.

  my $obj = TestClass->create(id => 1, foo => 'bar', baz=> 'blah');
  my $rule = UR::BoolExpr->resolve('TestClass', foo => 'bar);
  my $val = $context->infer_property_value_from_rule('baz', $rule);
  # val now is 'blah'

=item object_cache_size_highwater

  UR::Context->object_cache_size_highwater(5000);
  my $highwater = UR::Context->object_cache_size_highwater();

Set or get the value for the Context's object cache pruning high water
mark.  The object cache pruner will be run during the next C<get()> if the
cache contains more than this number of prunable objects.  See the 
L</Object Cache Pruner> section below for more information.

=item object_cache_size_lowwater

  UR::Context->object_cache_size_lowwater(5000);
  my $lowwater = UR::Context->object_cache_size_lowwater();

Set or get the value for the Context's object cache pruning high water
mark.  The object cache pruner will stop when the number of prunable objects
falls below this number.

=item prune_object_cache

  UR::Context->prune_object_cache();

Manually run the object cache pruner.

=item reload

  UR::Context->reload($object);
  UR::Context->reload('Some::Class', 'property_name', value);

Ask the context to load an object's data from an underlying Context, even if
the object is already cached.  With a single parameter, it will use that
object's ID parameters as the basis for querying the data source.  C<reload>
will also accept a class name and list of key/value parameters the same as
C<get>.

=item _light_cache

  UR::Context->_light_cache(1);

Turn on or off the light caching flag.  Light caching alters the behavior 
of the object cache in that all object references in the cache are made weak
by Scalar::Util::weaken().  This means that the application code must keep
hold of any object references it wants to keep alive.  Light caching defaults
to being off, and must be explicitly turned on with this method.

=back

=head1 Data Concurrency

Currently, the Context is optimistic about data concurrency, meaning that 
it does very little to prevent clobbering data in underlying Contexts during
a commit() if other processes have changed an object's data after the Context
has cached and object.  For example, a database has an object with ID 1 and
a property with value 'bob'.  A program loads this object and changes the
property to 'fred', but does not yet commit().  Meanwhile, another program
loads the same object, changes the value to 'joe' and does commit().  Finally
the first program calls commit().  The final value in the database will be
'fred', and no exceptions will be raised.

As part of the caching behavior, the Context keeps a record of what the
object's state is as it's loaded from the underlying Context.  This is how 
the Context knows what object have been changed during C<commit()>.

If an already cached object's data is reloaded as part of some other query,
data consistency of each property will be checked.  If there are no
conflicting changes, then any differences between the object's initial state
and the current state in the underlying Context will be applied to the
object's notion of what it thinks its intial state is.

In some future release, UR may support additional data concurrency methods
such as pessimistic concurrency: check that the current state of all
changed (or even all cached) objects in the underlying Context matches the
initial state before committing changes downstream.  Or allowing the object
cache to operate in write-through mode for some or all classes.

=head1 Internal Methods

There are many methods in UR::Context meant to be used internally, but are
worth documenting for anyone interested in the inner workings of the Context
code.

=over 4

=item _create_import_iterator_for_underlying_context

  $subref = $context->_create_import_iterator_for_underlying_context(
                          $boolexpr, $data_source, $serial_number
                      );
  $next_obj = $subref->();

This method is part of the object loading process, and is called by
L</get_objects_for_class_and_rule> when it is determined that the requested
data does not exist in the object cache, and data should be brought in from
another, underlying Context.  Usually this means the data will be loaded
from an external data source.

C<$boolexpr> is the L<UR::BoolExpr> rule, usually from the application code.

C<$data_source> is the L<UR::DataSource> that will be used to load data from.

C<$serial_number> is used by the object cache pruner.  Each object loaded
through this iterator will have $serial_number in its C<__get_serial> hashref
key.

It works by first getting an iterator for the data source (the
C<$db_iterator>).  It calls L</_get_template_data_for_loading> to find out
how data is to be loaded and whether this request spans multiple data
sources.  It calls L</__create_object_fabricator_for_loading_template> to get
a list of closures to transform the primary data source's data into UR
objects, and L</_create_secondary_loading_closures> (if necessary) to get
more closures that can load and join data from the primary to the secondary
data source(s).

It returns a subref that works as an iterator, loading and returning objects
one at a time from the underlying context into the current context.  It 
returns undef when there are no more objects to return.

The returned iterator works by first asking the C<$db_iterator> for the next
row of data as a listref.  Asks the secondary data source joiners whether
there is any matching data.  Calls the object fabricator closures to convert
the data source data into UR objects.  If any of the object requires
subclassing, then additional importing iterators are created to handle that.
Finally, the objects matching the rule are returned to the caller one at a
time.

=item _get_template_data_for_loading

  my $template_data = $context->_get_template_data_for_loading(
                                    $data_source,
                                    $boolexpr_tmpl
                                );
  my($template_data, @addl_info) = $context->_get_template_data_for_loading(
                                                 $data_source,
                                                 $boolexpr_tmpl
                                             );

When a request is made that will hit one or more data sources,
C<_get_template_data_for_loading> is used to call a method of the same name
on the data source.  It retuns a hashref used by many other parts of the 
object loading system, and describes what data source to use, how to query
that data source to get the objects, how to use the raw data returned by
the data source to construct objects and how to resolve any delegated
properties that are a part of the rule.

C<$data_source> is a L<UR::DataSource> object ID.  C<$coolexpr_tmpl> is a
L<UR::BoolExpr::Template> object.

In the common case, the query will only use one data source, and this method
returns that data directly.  But if the primary data source sets the 
C<joins_across_data_sources> key on the data structure as may be the case
when a rule involves a delegated property to a class that uses a different
data source, then this methods returns an additional list of data.  For
each additional data source needed to resolve the query, this list will have
three items:

=over 2

=item 1.

The secondary data source ID

=item 2. 

A listref of delegated L<UR::Object::Property> objects joining the primary
data source to this secondary data source.

=item 3. 

A L<UR::BoolExpr::Template> rule template applicable against the secondary
data source

=back

=item _create_secondary_rule_from_primary

  my $new_rule = $context->_create_secondary_rule_from_primary(
                               $primary_rule,
                               $delegated_properties,
                               $secondary_rule_tmpl
                           );

When resolving a request that requires multiple data sources,
this method is used to construct a rule against applicable against the
secondary data source.  C<$primary_rule> is the L<UR::BoolExpr> rule used
in the original query.  C<$delegated_properties> is a listref of
L<UR::Object::Property> objects as returned by
L</_get_template_data_for_loading()> linking the primary to the secondary data
source.  C<$secondary_rule_tmpl> is the rule template, also as returned by 
L</_get_template_data_for_loading()>.

=item _create_secondary_loading_closures

  my($obj_importers, $joiners) = $context->_create_secondary_loading_closures(
                                               $primary_rule_tmpl,
                                               @addl_info);

When reolving a request that spans multiple data sources,
this method is used to construct two lists of subrefs to aid in the request.
C<$primary_rule_tmpl> is the L<UR::BoolExpr::Template> rule template made
from the original rule.  C<@addl_info> is the same list returned by
L</_get_template_data_for_loading>.  For each secondary data source, there
will be one item in the two listrefs that are returned, and in the same
order.

C<$obj_importers> is a listref of subrefs used as object importers.  They
transform the raw data returned by the data sources into UR objects.

C<$joiners> is also a listref of subrefs.  These closures know how the
properties link the primary data source data to the secondary data source.
They take the raw data from the primary data source, load the next row of
data from the secondary data source, and returns the secondary data that
successfully joins to the primary data.  You can think of these closures as
performing the same work as an SQL C<join> between data in different data
sources.

=item __create_object_fabricator_for_loading_template

  $subref = $context->__create_object_fabricator_for_loading_template(
                          $loading_tmpl_hashref,
                          $template_data,
                          $boolexpr,
                          $boolexpr_tmpl,
                          $boolexpr_values_listref,
                          $data_source);
  $obj = $subref->($data_source_data_listref);

This method is part of the object loading process, and is called by
L</get_objects_for_class_and_rule> to transform a row of data returned by
a data source iterator into a UR object.  

For each class involved in a get request, the system prepares a loading
template that describes which columns of the data source data are to be
used to construct an instance of that class.  For example, in the case where
a get() is done on a child class, and the parent and child classes store data
in separate tables linked by a relation-property/foreign-key, then the query
against the data source will involve and SQL join (for RDBMS data sources).
That join will produce a result set that includes data from both tables.

The C<$loading_tmpl_hashref> will have information about which columns of
that result set map to which properties of each involved class.  The heart
of the fabricator closure is a list slice extracting the data for that class
and assigning it to a hash slice of properties to fill in the initial object
data for its class.  The remainder of the closure is bookkeeping to keep the
object cache ($UR::Context::all_objects_loaded) and query cache 
($UR::Context::all_params_loaded) consistent.

The interaction of the object fabricator, the query cache, object cache
pruner and object loading iterators that may or may not have loaded all
their data requires that the object fabricators keep a list of changes they
plan to make to the query cache instead of applying them directly.  When
the Underlying Context Loading iterator has loaded the last row from the
Data Source Iterator, it calls C<finalize()> on the object fabricator to
tell it to go ahead and apply its changes; essentially treating that
data as a transaction.

=item _cache_is_complete_for_class_and_normalized_rule

  ($is_cache_complete, $objects_listref) =
      $context->_cache_is_complete_for_class_and_normalized_rule(
                    $class_name, $boolexpr
                );

This method is part of the object loading process, and is called by
L</get_objects_for_class_and_rule> to determine if the objects requested
by the L<UR::BoolExpr> C<$boolexpr> will be found entirely in the object
cache.  If the answer is yes then C<$is_cache_complete> will be true.
C<$objects_listef> may or may not contain objects matching the rule from
the cache.  If that list is not returned, then
L</get_objects_for_class_and_rule> does additional work to locate the
matching objects itself via L</_get_objects_for_class_and_rule_from_cache>

It does its magic by looking at the C<$boolexpr> and loosely matching it
against the query cache C<$UR::Context::all_params_loaded>

=item _get_objects_for_class_and_rule_from_cache

  @objects = $context->_get_objects_for_class_and_rule_from_cache(
                           $class_name, $boolexpr
                       );

This method is called by L</get_objects_for_class_and_rule> when 
L<_cache_is_complete_for_class_and_normalized_rule> says the requested
objects do exist in the cache, but did not return those items directly.

The L<UR::BoolExpr> C<$boolexpr> contains hints about how the matching data
is likely to be found.  Its C<_context_query_strategy> key will contain
one of three values

=over 2

=item 1.  all

This rule is against a class with no filters, meaning it should return every
member of that class.  It calls C<$class-E<gt>all_objects_loaded> to extract
all objects of that class in the object cache.

=item 2. id

This rule is against a class and filters by only a single ID, or a list of
IDs.  The request is fulfilled by plucking the matching objects right out
of the object cache.

=item 3.

The category for any other rule.  This request is fulfilled by getting a
previously created L<UR::Object::Index> for this rule, or creating a new
UR::Object::Index, and calling L<UR::Object::Index/all_objects_matching>.

=back

=item _loading_was_done_before_with_a_superset_of_this_params_hashref

  $bool = $context->_loading_was_done_before_with_a_superset_of_this_params_hashref(
                        $class_name,
                        $params_hashref
                    );

This method is used by L</_cache_is_complete_for_class_and_normalized_rule>
to determine if the requested data was asked for previously, either from a
get() asking for a superset of the current request, or from a request on
a parent class of the current request.

For example, if a get() is done on a class with one param:

  @objs = ParentClass->get(param_1 => 'foo');

And then later, another request is done with an additional param:

  @objs2 = ParentClass->get(param_1 => 'foo', param_2 => 'bar');

Then the first request must have returned all the data that could have
possibly satisfied the second request, and so the system will not issue
a query against the data source.

As another example, given those two previously done queries, if another
get() is done on a class that inherits from ParentClass

  @objs3 = ChildClass->get(param_1 => 'foo');

again, the first request has already loaded all the relevent data, and
therefore won't query the data source.

=item _sync_databases

  $bool = $context->_sync_databases();

Starts the process of committing all the Context's changes to the external
data sources.  _sync_databases() is the workhorse behind L</commit>.

First, it finds all objects with changes.  Checks those changed objects
for validity with C<$obj-E<gt>invalid>.  If any objects are found invalid,
then _sync_databases() will fail.  Finally, it bins all the changed objects
by data source, and asks each data source to save those objects' changes.
It returns true if all the data sources were able to save the changes,
false otherwise.

=item _reverse_all_changes

  $bool = $context->_reverse_all_changes();

_reverse_all_changes() is the workhorse behind L</rollback>.  

For each class, it goes through each object of that class.  If the object
is a L<UR::Object::Ghost>, representing a deleted object, it converts the
ghost back to the live version of the object.  For other classes, it makes
a list of properties that have changed since they were loaded (represented
by the C<db_committed> hash key in the object), and reverts those changes
by using each property's accessor method.

=back

=head1 The Object Cache

The object cache is integral to the way the Context works, and also the main
difference between UR and other ORMs.  Other systems do no caching and
require the calling application to hold references to any objects it 
is interested in.  Say one part of the app loads data from the database and
gives up its references, then if another part of the app does the same or
similar query, it will have to ask the database again.

UR handles caching of classes, objects and queries to avoid asking the data
sources for data it has loaded previously.  The object cache is essentially
a software transaction that sits above whatever database transaction is
active.  After objects are loaded, any changes, creations or deletions exist
only in the object cache, and are not saved to the underlying data sources
until the application explicitly requests a commit or rollback.  

Objects are returned to the application only after they are inserted into
the object cache.  This means that if disconnected parts of the application
are returned objects with the same class and ID, they will have references
to the same exact object reference, and changes made in one part will be
visible to all other parts of the app.  An unchanged object can be removed
from the object cache by calling its C<unload()> method.

Since changes to the underlying data sources are effectively delayed, it is
possible that the application's notion of the object's current state does
not match the data stored in the data source.  You can mitigate this by using
the C<load()> class or object method to fetch the latest data if it's a
problem.  Another issue to be aware of is if multiple programs are likely
to commit conflicting changes to the same data, then whichever applies its
changes last will win; some kind of external locking needs to be applied.
Finally, if two programs attempt to insert data with the same ID columns
into an RDBMS table, the second application's commit will fail, since that
will likely violate a constraint.

=head2 Object Change Tracking

As objects are loaded from their data sources, their properties are
initialized with the data from the query, and a copy of the same data is
stored in the object in its C<db_committed> hash key.  Anyone can ask the
object for a list of its changes by calling C<$obj-E<gt>changed>.
Internally, changed() goes through all the object's properties, comparing
the current values in the object's hash with the same keys under
'db_committed'.  

Objects created through the C<create()> class method have no 'db_committed',
and so the object knows it it a newly created object in this context.

Every time an object is retrieved with get() or through an iterator, it is
assigned a serial number in its C<__get_serial> hash key from the
C<$UR::Context::GET_SERIAL> counter.  This number is unique and increases
with each get(), and is used by the L</Object Cache Pruner> to expire the
least recently requested data.

Objects also track what parameters have been used to get() them in the hash
C<$obj-E<gt>{load}-E<gt>{param_key}>.  This is a copy of the data in
C<$UR::Context::all_params_loaded-E<gt>{$class_name}>.  For each rule
ID, it will have a count of the number of times that rule was used in a get().

=head2 Deleted Objects and Ghosts

Calling delete() on an object is tracked in a different way.  First, a new
object is created, called a ghost.  Ghost classes exist for every
class in the application and are subclasses of L<UR::Object::Ghost>.  For
example, the ghost class for MyClass is MyClass::Ghost.  This ghost object
is initialized with the data from the original object.  The original object
is removed from the object cache, and is reblessed into the UR::DeletedRef
class.  Any attempt to interact with the object further will raise an
exception.

Ghost objects are not included in a get() request on the regular class,
though the app can ask for them specificly using
C<MyClass::Ghost-E<gt>get(%params)>.

Ghost classes do not have ghost classes themselves.  Calling create() or
delete() on a Ghost class or object will raise an exception.  Calling other
methods on the Ghost object that exist on the original, live class will
delegate over to the live class's method.

=head2 all_objects_are_loaded

C<$UR::Context::all_objects_are_loaded> is a hashref keyed by class names.
If the value is true, then L</_cache_is_complete_for_class_and_normalized_rule>
knows that all the instances of that class exist in the object cache, and
it can avoid asking the underlying context/datasource for that class' data.

=head2 all_params_loaded

C<$UR::Context::all_params_loaded> is a two-level hashref.  The first level
is class names.  The second level is rule (L<UR::BoolExpr>) IDs.  The values
are how many times that class and rule have been involved in a get().  This
data is used by L</_loading_was_done_before_with_a_superset_of_this_params_hashref>
to determine if the requested data will be found in the object cache for
non-id queries.

=head2 all_objects_loaded

C<$UR::Context::all_objects_loaded> is a two-level hashref.  The first level
is class names.  The second level is object IDs.  Every time an object is
created, defined or loaded from an underlying context, it is inserted into
the C<all_objects_loaded> hash.  For queries involving only ID properties,
the Context can retrieve them directly out of the cache if they appear there.

The entire cache can be purged of non-infrastructional objects by calling
L</clear_cache>.

=head2 Object Cache Pruner

The default Context behavior is to cache all objects it knows about for the
entire life of the process.  For programs that churn through large amounts 
of data, or live for a long time, this is probably not what you want.  

The Context has two settings to loosely control the size of the object
cache.  L</object_cache_size_highwater> and L</object_cache_size_lowwater>.
As objects are created and loaded, a count of uncachable objects is kept
in C<$UR::Context::all_objects_cache_size>.  The first part of 
L</get_objects_for_class_and_rule> checks to see of the current size is
greater than the highwater setting, and call L</prune_object_cache> if so.

prune_object_cache() works by looking at what C<$UR::Context::GET_SERIAL>
was the last time it ran, and what it is now, and making a guess about 
what object serial number to use as a guide for removing objects by starting
at 10% of the difference between the last serial and the current value,
called the target serial.


It then starts executing a loop as long as C<$UR::Context::all_objects_cache_size>
is greater than the lowwater setting.  For each uncachable object, if its
C<__get_serial> is less than the target serial, it is weakened from any
L<UR::Object::Index>es it may be a member of, and then weakened from the
main object cache, C<$UR::Context::all_objects_loaded>.

The application may lock an object in the cache by calling C<__strengthen__> on
it,  Likewise, the app may hint to the pruner to throw away an object as 
soon as possible by calling C<__weaken__>.

=head1 SEE ALSO

L<UR::Context::Root>, L<UR::Context::Process>, L<UR::Object>,
L<UR::DataSource>, L<UR::Object::Ghost>

=cut

