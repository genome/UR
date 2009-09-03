# A base class supplying error, warning, status, and debug facilities.
# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package UR::ModuleBase;

BEGIN {
    use Class::Autouse;
    no strict;
    no warnings;
    *can = $Class::Autouse::ORIGINAL_CAN;
    *isa = $Class::Autouse::ORIGINAL_ISA;
}

=pod

=head1 NAME

UR::ModuleBase - Error, status, and warning messaging for derived packages

=head1 SYNOPSIS

    # common usage
    
    sub foo {
        my $self = shift;
        ...
        if ($problem) {           
            $self->error_message("Something went wrong...");
            return;
        }
        return 1;
    }
    
    unless ($obj->foo) {
        print STDERR $obj->error_string;
    }
    
    # A complete object is made with each error, staus,
    # or warning message with detail about the context in 
    # which it was created.
    
    # Some of the details are accessible directly on the object/class:
    $string       = $obj->error_string;
    $text         = $obj->error_text;
    $package_name = $obj->error_package;
    @call_stack   = $obj->error_call_stack;
    $time         = $obj->error_time;

    # The developer can also get the message object directly
    # and examine the properties.
    $msg_obj      = $obj->error_object;
        $string         = $msg_obj->string; 
        $text           = $msg_obj->text;
        $package_name   = $msg_obj->package_name;
        @call_stack     = $msg_obj->call_stack;
        $time           = $msg_obj->time;
        $type           = $msg_obj->type;  # "error"
        $owner          = $msg_obj->owner; # $obj

    # WARNING: error_message will return the last error specified
    # on that object/class.  It is not automatically reset when
    # other methods are called which work without error.
    
    # When no error is explicitly found, a check is made against
    # the last error in general (UR::ModuleBase->error_message)
    # and call stacks are compared.  If it occurred in something    
    # called by the caller.
    
    
=head1 DESCRIPTION

This is a base class for packages, classes, and objects which need to
set/get error, warning, debug, and status messages on themselves,
their class, and their parent class(es).

=head1 METHODS

These methods create and change message handlers.

=cut

# set up package
require 5.6.0;
use warnings;
use strict;
our $VERSION = '0.6';

# set up module
use Carp;
use IO::Handle;

=pod

=item C<class>

  $class = $obj->class;

This returns the class name of a class or an object.
It is exactly equivalent to:

    (ref($self) ? ref($self) : $self)

=cut

sub class
{
    my $class = shift;
    $class = ref($class) if ref($class);
    return $class;
}

=pod 

=item C<super_class>

  $obj->super_class->super_class_method1();
  $obj->super_class->super_class_method2();

This returns the super-class name of a class or an object.
It is exactly equivalent to:  
    $self->class . "::SUPER"

Note that MyClass::SUPER is specially defined to include all
of the items in the classes in @MyClass::ISA, so in a multiple
inheritance scenario:

  $obj->super_class->super_class_method1();
  $obj->super_class->super_class_method2();

...could have super_class_method1() in one parent class
and super_class_method2() in another parent class.

=cut

sub super_class { shift->class . "::SUPER" }

=pod 

=item C<super_can>

  $sub_ref = $obj->super_can('func');

This method determines if any of the super classes of the C<$obj>
object can perform the method C<func>.  If any one of them can,
reference to the subroutine that would be called (determined using a
depth-first search of the C<@ISA> array) is returned.  If none of the
super classes provide a method named C<func>, C<undef> is returned.

=cut

sub super_can
{
    my $super_class = shift->super_class;
    
    # Handle the case in which the super_class has overridden
    # UNIVERSAL::can()
    my $super_can = $super_class->can("can");
    
    # Call the correct can() on the super_class with the normal params.
    return $super_can->($super_class,@_);
    
    #no strict;
    #foreach my $parent_class (@{$class . '::ISA'})
    #{
    #    my $code = $parent_class->can(@_);
    #    return $code if $code;
    #}
    #return;
}

=pod

=item C<inheritance>

  @classes = $obj->inheritance;

This method returns a depth-first list of all the classes (packages)
that the class that C<$obj> was blessed into inherits from.  This
order is the same order as is searched when searching for inherited
methods to execute.  If the class has no super classes, an empty list
is returned.  The C<UNIVERSAL> class is not returned unless explicitly
put into the C<@ISA> array by the class or one of its super classes.

=cut

sub inheritance {
    my $self = $_[0];    
    my $class;
    $class = ref($self) || $self;
#my @c0 = caller(0);
#my @c1 = caller(1);
#print STDERR "inheritance $class @_ :  $c1[3] $c0[2]\n";
#print STDERR "inheritance $class\n";
    no strict;
    my @parent_classes = @{$class . '::ISA'};

    my @ordered_inheritance;
    foreach my $parent_class (@parent_classes) {
    push @ordered_inheritance, $parent_class, ($parent_class eq 'UR' ? () : inheritance($parent_class) );
    }

    return @ordered_inheritance;
}

=pod

=item C<parent_classes>

  MyClass->parent_classes;

This returns the immediate parent class, or parent classes in the case
of multiple inheritance.  In no case does it follow the inheritance
hierarchy as ->inheritance() does.

=cut

sub parent_classes
{
    my $self = $_[0];
    my $class = ref($self) || $self;
    no strict;
    no warnings;
    my @parent_classes = @{$class . '::ISA'};
    return (wantarray ? @parent_classes : $parent_classes[0]);
}

=pod

=item C<base_dir>

  MyModule->base_dir;

This returns the base directory for a given module, in which the modules's 
supplemental data will be stored, such as config files and glade files,
data caches, etc.

It uses %INC.

=cut

sub base_dir
{
    my $self = shift;
    my $class = ref($self) || $self;    
    $class =~ s/\:\:/\//g;
    my $dir = $INC{$class . '.pm'} || $INC{$class . '.pl'};
    die "Failed to find module $class in \%INC: " . Dumper(%INC) unless ($dir);
    $dir =~ s/\.p[lm]\s*$//;
    return $dir;
}

=pod

=item C<AUTOLOAD>

This package impliments AUTOLOAD so that derived classes can use
AUTOSUB instead of AUTOLOAD.

When a class or object has a method called which is not found in the
final class or any derived classes, perl checks up the tree for
AUTOLOAD.  We impliment AUTOLOAD at the top of the tree, and then
check each class in the tree in order for an AUTOSUB method.  Where a
class implements AUTOSUB, it will recieve a function name as its first
parameter, and it is expected to return either a subroutine reference,
or undef.  If undef is returned then the inheritance tree search will
continue.  If a subroutine reference is returned it will be executed
immediately with the @_ passed into AUTOLOAD.  Typically, AUTOSUB will
be used to generate a subroutine reference, and will then associate
the subref with the function name to avoid repeated calls to AUTOLOAD
and AUTOSUB.

Why not use AUTOLOAD directly in place of AUTOSUB?

On an object with a complex inheritance tree, AUTOLOAD is only found
once, after which, there is no way to indicate that the given AUTOLOAD
has failed and that the inheritance tree trek should continue for
other AUTOLOADS which might impliment the given method.

Example:

    package MyClass;
    our @ISA = ('UR');
    ##- use UR;    
    
    sub AUTOSUB
    {
        my $sub_name = shift;        
        if ($sub_name eq 'foo')
        {
            *MyClass::foo = sub { print "Calling MyClass::foo()\n" };
            return \&MyClass::foo;
        }
        elsif ($sub_name eq 'bar')
        {
            *MyClass::bar = sub { print "Calling MyClass::bar()\n" };
            return \&MyClass::bar;
        }
        else
        { 
            return;
        }
    }

    package MySubClass;
    our @ISA = ('MyClass');
    
    sub AUTOSUB
    {
        my $sub_name = shift;
        if ($sub_name eq 'baz')
        {
            *MyClass::baz = sub { print "Calling MyClass::baz()\n" };
            return \&MyClass::baz;
        }
        else
        { 
            return;
        }
    }

    package main;
    
    my $obj = bless({},'MySubClass');    
    $obj->foo;
    $obj->bar;
    $obj->baz;

=cut

our $AUTOLOAD;
sub AUTOLOAD {
    
    my $self = $_[0];
    
    # The debugger can't see $AUTOLOAD.  This is just here for debugging.
    my $autoload = $AUTOLOAD; 
    
    $autoload =~ /(.*)::([^\:]+)$/;            
    my $package = $1;
    my $function = $2;

    return if $function eq 'DESTROY';

    unless ($package) {
        Carp::confess("Failed to determine package name from autoload string $autoload");
    }

    if (my $subref = $package->_smart_can($function)) {
        goto $subref;
    }

    # switch these to use Class::AutoCAN / CAN?
    no strict;
    no warnings;
    my @classes = grep {$_} ($self, inheritance($self) );
    for my $class (@classes) {
        if (my $AUTOSUB = $class->can("AUTOSUB"))
            # FIXME The above causes hard-to-read error messages if $class isn't really a class or object ref
            # The 2 lines below should fix the problem, but instead make other more impoartant things not work
            #my $AUTOSUB = eval { $class->can('AUTOSUB') };
        #if ($AUTOSUB) {
        {                    
            if (my $subref = $AUTOSUB->($function,@_)) {
                goto $subref;
            }
        }
    }

    if ($autoload and $autoload !~ /::DESTROY$/) {
        my $subref = \&Carp::confess;
        @_ = ("Can't locate object method \"$function\" via package \"$package\" (perhaps you forgot to load \"$package\"?)");
        goto $subref;
    }
}

=pod

=item C<can>

  MyClass->can('some_subroutine_name');

The normal version of can() is in UNIVERSAL.  We override it here so
that functions implimented by AUTOSUB will be found where
UNIVERSAL::can() would fail to do so.

=cut

sub _smart_can
{
    
    my ($self,$function) = @_;
    #print "CAN @_\n";

    # Default functionality.  Defer upstream.  This will check all classes.
    # For a real/normal function.
    # This is disabled because UNIVERSAL::can somehow returns a subref which puts us in an infinite loop...
    #my $code = UNIVERSAL::can($self,$function);
    #return $code if $code;

    return if $function  =~ /^(id|unique)_properties_override$/;    

    my $class = ref($self) || $self;

    if ($self->isa("UR::Object")) {
        my $delegate_method = $function;
        my $remote_method = "";
        my $src;
        for (1) {
            my $code = $self->SUPER::can($delegate_method);
            if ($code) {
                no strict 'refs';
                next;
                Carp::cluck();
                $src = qq|
                    # dynamically generated
                    sub ${class}::${function} {
                        my \$self = shift;
                        my \$delegate = \$self->$delegate_method;
                        return \$delegate->$remote_method;     
                    }
                |;
                $src =~ s/^\s{20}//mg;
            }
            else {
                my $reference;
                if (
                    $reference = UR::Object::Reference->get(
                        class_name => $class,
                        accessor_name_for_object => $delegate_method,
                    )
                ) {
                    # generate a method to return an object
                    my $accessor_name_for_id = $reference->accessor_name_for_id;
                    my $r_class_name = $reference->r_class_name;
                    $src = qq|
                        # dynamically generated object accessor
                        sub ${class}::${function} {
                            my \$self = shift;
                            my \$obj = $r_class_name->get(\$self->$accessor_name_for_id);
                            return \$obj;     
                        }
                    |;
                    $src =~ s/^\s{24}//mg;
                    $src =~ s/^\s*//;
                }
                elsif (                
                    $reference = UR::Object::Reference->get(
                        class_name => $class,
                        accessor_name_for_id => $delegate_method,
                    ) 
                ) {
                    # generate a method to return a value                    
                    print "make method $delegate_method to return a value for $class\n";
                }
            }
            
            # failed to delegate, back through the method name
            # and try subsets...
            if ($delegate_method =~ /(^.+)_([^_]+)$/) {
                $delegate_method = $1;
                $remote_method = $2 . ($remote_method ? "_" . $remote_method : "");
                redo;
            }
        }
        if ($src) {
            #print $src;
            eval $src;
            if ($@) {
                Carp::confess("Error creating dynamic accessor for delegated method call: $@");
            }
            return $class->can($function);
        }
    }

    # See if any of the classes can autogenerate a function with the desired
    # name.  Use it if found.
    no strict;
    for my $class (grep {$_} ($self, inheritance($self) ))
    {
    if (my $AUTOSUB = UNIVERSAL::can($class,"AUTOSUB"))
    {                    
        if (my $subref = $AUTOSUB->($function,$class))
        {
        return $subref;
        }
    }
    }
    
    # Return nothing if we found nothing.
    return;
}

=pod

=item methods

Undocumented.

=cut

sub methods
{
    my $self = shift;
    my @methods;
    my %methods;
    my ($class, $possible_method, $possible_method_full, $r, $r1, $r2);
    no strict; 
    no warnings;

    for $class (reverse($self, $self->inheritance())) 
    { 
        print "$class\n"; 
        for $possible_method (sort grep { not /^_/ } keys %{$class . "::"}) 
        {
            $possible_method_full = $class . "::" . $possible_method;
            
            $r1 = $class->can($possible_method);
            next unless $r1; # not implemented
            
            $r2 = $class->super_can($possible_method);
            next if $r2 eq $r1; # just inherited
            
            {
                push @methods, $possible_method_full; 
                push @{ $methods{$possible_method} }, $class;
            }
        } 
    }
    print Dumper(\%methods);
    return @methods;
}

=pod

=item C<context_return>

  return MyClass->context_return(@return_values);

Attempts to return either an array or scalar based on the calling context.
Will die if called in scalar context and @return_values has more than 1
element.

=cut

sub context_return {
    my $class = shift;
    return unless defined wantarray;
    return @_ if wantarray;
    Carp::confess("Method on $class called in scalar context, but " . scalar(@_) . " items need to be returned") if @_ > 1;
    return $_[0];
}


=over

=item message_types

  @types = UR::ModuleBase->message_types;
  UR::ModuleBase->message_types(@more_types);

With no arguments, this method returns all the types of messages that
this class handles.  With arguments, it adds a new type to the
list.

Note that the addition of new types is not fully supported/implemented
yet.

=cut

our @message_types = qw(error status warning debug);
sub message_types
{
    my $class = shift;
    if (@_)
    {
        push(@message_types, @_);
    }
    return @message_types;
}

# create methods to set and return messages
foreach my $type (@message_types)
{
    no strict 'refs';
    # This method looks like a r/w accessor, but internally does extra work.
    # On write it actually creates a message object from the passed-in text (and call stack info).
    # On read it, retrieves such object, if it exists, and returns the ->text property of it.
    # Other methods below allow deeper introspection to the last message logged for an object/class. 
    my $accessor = sub {
        my $msg = shift->message_object($type, @_);
        return ($msg ? $msg->text : undef);
    };
    *{"${type}_message"} = $accessor; 

    # methods to access different features of the message
    foreach my $func_suffix (qw(string text package_name call_stack time_stamp
                                level))
    {
        # This is used in the closure below.
        # It must be lexically scoped INSIDE of the for loop.
        my $mobj_method = $func_suffix;

        # Set the class method up.
        my $fname = "${type}_${func_suffix}";
        *$fname = sub
        {
            my $self = shift;
            my $message_object
                = (ref($self) ? $self->{"${type}_message"} : ${"${self}::${type}_message"});
            return unless $message_object;
            return $message_object->$mobj_method(@_);
        }
    }
}

=pod

=item message_callback

  $sub_ref = UR::ModuleBase->message_callback($type);
  UR::ModuleBase->message_callback($type, $sub_ref);

This method returns and optionally sets the subroutine that handles
messages of a specific type.

=cut

# set or return a callback that has been created for a message type
our %message_callback;
sub message_callback
{
    my $self = shift;
    my ($type, $callback) = @_;

    # set the callback for a given message type if callback provided
    if (@_ > 1)
    {
        $message_callback{$type} = $callback;
    }
    return $message_callback{$type};
}

# create message object, fire callbacks, and set message on parents
sub message_object
{
    my $self = shift;
    # see how we were called
    if (@_ < 2)
    {
        no strict 'refs';
        # return the message object
        my ($type) = @_;
        my $mobj = (ref($self) ? $self->{"${type}_message"} : ${"${self}::${type}_message"});
        unless ($mobj) 
        {
            # See if the most recent message was directly or 
            # indirectly on $self in our current scope.
            my $last_message = ${"UR::ModuleBase::${type}_message"};
            if ($last_message) 
            {
                # Get both call stacks.
                my @s1 = $last_message->call_stack;
                my $s2 = _current_call_stack();
                                                
                # Make sure the upper call of the last error
                # matches all of our current upper call stack.
                for (my $n=$#$s2-1; $n >=0; $n--) {
                    if ($s1[$n] ne $s2->[$n]) {
                        # call stack mismatch
                        return;
                    }
                }                
                
                # Make sure that the last message 
                # occurred under a call to $self. 
                my $last_message_sub_at_this_scope = $s1[$#$s2];
                unless ($last_message_sub_at_this_scope) {
                    return;
                }
                my ($pkg,$sub) = 
                    ($last_message_sub_at_this_scope =~ /^\s*(\w+)::([^\:\W]+)/);
                unless ($self->isa($pkg) and $self->can($sub)) {
                    # The last message did not occur under this object.
                    return;
                }
                
                # No mismatch.  The message occurred in the current function,
                # and under the object we're testing.  Steal the message.
                $mobj = $last_message;
                $s1[-1] =~ s/^(\s+).* called at/ logged at/;
                $s1[-1] = $1 . ucfirst($type) . $s1[-1];
                $self->message_object (
                    "warning",
                    "Found unpropagated error message.  Set $type message before return from: ${pkg}::${sub}:\n"
                        . join("\n",@s1)
                );
            }            
        }
        return $mobj;
    }
    else
    {
        # create a message object
        my ($type, $text, $level) = @_;
        $text ||= '(not set)';
        $level ||= 1;
        my $class = $self->class;
        my $id = (ref($self) ? ($self->can("id") ? $self->id : $self) : $self);

        # Turn the message into an object with all of the goodies.
        my $message_object = UR::ModuleBase::Message->create
        (
            text         => $text,
            level        => $level,
            package_name => ((caller(0))[0]),
            call_stack   => ($type eq "error" ? _current_call_stack() : []),
            time_stamp   => time,
            type         => $type,
            owner_class  => $class,
            owner_id     => $id,
        );

        no strict 'refs';

        # Get existing values for the class and object.
        my $class_old = ${"${class}::${type}_message"};
        my $object_old =  $self->{"${type}_message"} if (ref($self));

        # Fire the callback as appropriate.
        my $callback = $message_callback{$type};
        if ($callback)
        {
            $callback->($message_object,$self,$type,$class_old,$object_old);
        }
        elsif ($type ne 'debug')
        {
            # if no callback defined, print non-debug messages to stderr
            my $warn_txt = "$class: " . uc($type) . ": "
                . join(': ', (caller(2))[0, 2]) . ": $text";
            chomp($warn_txt);
            STDERR->print("$warn_txt\n");
        }

        # Set the value on the object, the class, and all parent classes.
        $self->{"${type}_message"} = $message_object if (ref($self));
        foreach my $set_class ($class, $class->inheritance)
        {
            no warnings;
            ${"${set_class}::${type}_message"} = $message_object;
        }

        # Return the message which was passed-in.
        return $message_object;
    }
}

sub _current_call_stack
{
    my @stack = reverse split /\n/, Carp::longmess("\t");

    # Get rid of the final line from carp, showing the line number
    # above from which we called it.
    pop @stack;

    # Get rid any other function calls which are inside of this
    # package besides the first one.  This allows wrappers to
    # get_message to look at just the external call stack.
    # (i.e. AUTOSUB above, set_message/get_message which called this,
    # and AUTOLOAD in UniversalParent)
    pop(@stack) while ($stack[-1] =~ /^\s*(UR::ModuleBase|UR)::/ && $stack[-2] && $stack[-2] =~ /^\s*(UR::ModuleBase|UR)::/);

    return \@stack;
}

# class that stores and manages messages
package UR::ModuleBase::Message;

use Scalar::Util qw(weaken);

##- use UR::Util;
UR::Util->generate_readonly_methods
(
    text         => undef,
    level        => undef,
    package_name => undef,
    call_stack   => [],
    time_stamp   => undef,
    owner_class  => undef,
    owner_id     => undef,
    type         => undef,
);

sub create
{
    my $class = shift;
    my $obj = {@_};
    bless ($obj,$class);
    weaken $obj->{'owner_id'} if (ref($obj->{'owner_id'}));

    return $obj;
}

sub owner
{
    my $self = shift;
    my ($owner_class,$owner_id) = ($self->owner_class, $self->owner_id);
    if (not defined($owner_id))
    {
        return $owner_class;
    }
    elsif (ref($owner_id))
    {
        return $owner_id;
    }
    else
    {
        return $owner_class->get($owner_id);
    }
}

sub string
{
    my $self = shift;
    "$self->{time} $self->{type}: $self->{text}\n";
}

sub _stack_item_params
{
    my ($self, $stack_item) = @_;
    my ($function, $parameters, @parameters);

    return unless ($stack_item =~ s/\) called at [^\)]+ line [^\)]+\s*$/\)/);

    if ($stack_item =~ /^\s*([^\(]*)(.*)$/)
    {
        $function = $1;
        $parameters = $2;
        @parameters = eval $parameters;
        return ($function, @parameters);
    }
    else
    {
        return;
    }
}

1;
__END__

=pod

=back

=head1 BUGS

Report bugs to <software@watson.wustl.edu>.

=head1 SEE ALSO

App(3), UR(3)

=head1 AUTHOR

Scott Smith <ssmith@watson.wustl.edu>

=cut

# $Header$
