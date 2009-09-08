package UR::Object;

use warnings;
use strict;

require UR;

use Scalar::Util;

our @ISA = ('UR::ModuleBase');
our $VERSION = $UR::VERSION;;

# Base object API 

sub class { ref($_[0]) || $_[0] }

sub id { $_[0]->{id} }

sub create {
    $UR::Context::current->create_entity(@_);
}

sub get {
    $UR::Context::current->query(@_);
}

sub delete {
    $UR::Context::current->delete_entity(@_);
}

# Meta API

sub __context__ {
    # In UR, a "context" handles inter-object references so they can cross
    # process boundaries, and interact with persistance systems automatically.

    # For efficiency, all context switches update a package-level value.

    # We will ultimately need to support objects recording their context explicitly
    # for things such as data maintenance operations.  This shouldn't happen
    # during "business logic".
    
    return $UR::Context::current;
}

sub __meta__  {
    # the class meta object
    # subclasses set this specifically for efficiency upon construction
    # the base class has a generic implementation for boostrapping
    Carp::cluck("using the default __meta__!");
    my $class_name = shift;
    return $UR::Context::all_objects_loaded->{"UR::Object::Type"}{$class_name};
}

sub __label_name__ {
    # override to provide default labeling of the object
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

sub __errors__ {
    # This is the basis for software constraint checking.
    # Return a list of values describing the problems on the object.

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

# Standard API for working with UR fixtures
#  boolean expressions
#  sets
#  iterators
#  viewers
#  mock objects

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

# Typically only used internally by UR except when debugging.

sub __changes__ {
    # Return a list of changes present on the object _directly_.
    # This is really only useful internally because the boundary of the object
    # is internal/subjective. 
 
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

sub __signal_change__ {
    # all mutable property accessors ("setters" call this method to tell the 
    # current context about a state change.
    $UR::Context::current->add_change_to_transaction_log(@_);
}

sub __define__ {
    # This is used internally to "virtually load" things.

    # Simply assert they already existed externally, and act as though they were just loaded...
    # It is used for classes defined in the source code (which is the default) by the "class {}" magic
    # instead of in some database, as we'd do for regular objects.  It is also used by some test cases.

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


# Handling of references within the current process

sub __weaken__ {
    # Mark this object as unloadable by the object cache pruner.
    # If the class has a data source, then a weakened object is dropped
    # at the first opportunity, reguardless of its __get_serial number.
    # For classes without a data source, then it will be dropped according to
    # the normal rules w/r/t the __get_serial (classes without data sources
    # normally are never dropped by the pruner)
    my $self = $_[0];
    delete $self->{'__strengthened'};
    $self->{'__weakened'} = 1;
}

sub __strengthen__ {
    # Indicate this object should never be unloaded by the object cache pruner
    my $self = $_[0];
    delete $self->{'__weakened'};
    $self->{'__strengthened'} = 1;
}

sub DESTROY {
    # Handle weak references in the object cache.
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

END {
    # Turn off monitoring of the DESTROY handler at application exit.
    # setting the typeglob to undef does not work. -sms
    delete $UR::Object::{DESTROY};
};

# This module implements the deprecated parts of the UR::Object API
require UR::ObjectDeprecated;

1;

