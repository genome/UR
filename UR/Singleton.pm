
package UR::Singleton;

use strict;
use warnings;
require UR;

UR::Object::Type->define(
    class_name => 'UR::Singleton',
    is => ['UR::Object'],
    english_name => 'ur singleton',
    is_abstract => 1,
);

sub _init_subclass {
    my $class_name = shift;
    my $class_meta_object = $class_name->get_class_object;

    # Write into the class's namespace the correct singleton overrides
    # to standard UR::Object methods.
    #print "init singleton $class_name\n";
 
    my $src;
    if ($class_meta_object->is_abstract) {
        $src =  qq|sub ${class_name}::_singleton_object { Carp::confess("${class_name} is an abstract singleton!  Select a concrete sub-class.") }|
            .   "\n"
            .   qq|sub ${class_name}::_singleton_class_name { Carp::confess("${class_name} is an abstract singleton!  Select a concrete sub-class.") }|
            .   "\n"
            .   qq|sub ${class_name}::_load { shift->_abstract_load(\@_) }|
    }
    else {
        $src =  qq|sub ${class_name}::_singleton_object { \$${class_name}::singleton or shift->_concrete_load() }|
            .   "\n"
            .   qq|sub ${class_name}::_singleton_class_name { '${class_name}' }|
            .   "\n"
            .   qq|sub ${class_name}::_load { shift->_concrete_load(\@_) }|
            .   "\n"            
            .   qq|sub ${class_name}::get { shift->_concrete_get(\@_) }|
            .   "\n"
            .   qq|sub ${class_name}::is_loaded { shift->_concrete_is_loaded(\@_) }|
        ;
    }
    
    #print "SOURCE $src\n";
    #eval "no warnings;\n" . $src;
    eval $src;
    Carp::confess($@) if $@;
    
    return 1;
}

# Abstract singletons havd a different load() method than concrete ones.
# We could do this with forking logic, but since many of the concrete methods
# get non-default handling, it's more efficient to do it this way.

sub _abstract_load {
    my $class = shift;
    my $params = $class->preprocess_params(@_);
    unless ($params->{id}) {
        use Data::Dumper;
        Carp::confess("Cannot load a singleton ($class) except by specific identity. " . Dumper($params));
    }
    my $subclass_name = $class->_resolve_subclass_name_for_id($params->{id});
    eval "use $subclass_name";    
    if ($@) {
        undef $@;
        return;
    }
    return $subclass_name->get();
}

# Concrete singletons have overrides to the most basic acccessors to
# accomplish class/object duality smoothly.

sub _concrete_get {
    if (@_ == 1 or (@_ == 2 and $_[0] eq $_[1])) {
        my $self = $_[0]->_singleton_object;
        return $self if $self;
    }
    return shift->_concrete_load(@_);
}

sub _concrete_is_loaded {
    if (@_ == 1 or (@_ == 2 and $_[0] eq $_[1])) {
        
        my $self = $_[0]->_singleton_object;
        return $self if $self;
    }
    return shift->SUPER::is_loaded(@_);
}

sub _concrete_load {
    my $class = shift;
    no strict 'refs';
    my $varref = \${ $class . "::singleton" };
    unless ($$varref) {
        my $id = $class->_resolve_id_for_subclass_name($class);        
        $$varref = $class->create_object(id => $id);    
        $$varref->{db_committed} = { %$$varref };
        $$varref->signal_change("load");
        Scalar::Util::weaken($$varref);
    }
    my $self = $class->_concrete_is_loaded(@_);
    return unless $self;
    unless ($self->init) {
        Carp::confess("Failed to initialize singleton $class!");
    }
    return $self;
}

# This is implemented in the singleton to do any post-load processing.

sub init {
    return 1;
}

# All singletons require special deletion logic since they keep a 
# weakened reference to the singleton.

sub delete_object {
    my $self = shift;
    my $class = $self->class;
    no strict 'refs';
    ${ $class . "::singleton" } = undef if ${ $class . "::singleton" } eq $self;
    $self->SUPER::delete_object(@_);
}

# In most cases, the id is the class name itself, but this is not necessary.

sub _resolve_subclass_name_for_id {
    my $class = shift;
    my $id = shift;
    return $id;
}

sub _resolve_id_for_subclass_name {
    my $class = shift;
    my $subclass_name = shift;
    return $subclass_name;
}

sub create {
    my $class = shift;
    my $params = $class->preprocess_params(@_);
    
    Carp::confess("No singleton ID class specified for constructor?") unless $params->{id};
    my $subclass = $class->_resolve_subclass_name_for_id($params->{id});
    
    eval "use $subclass";
    unless ($subclass->isa(__PACKAGE__)) {
        eval '@' . $subclass . "::ISA = ('" . __PACKAGE__ . "')";
    }
        
    return $subclass->SUPER::create(@_);
}

1;

