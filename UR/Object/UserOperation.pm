# Methods describing possible operations a user can perform on an object.
# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package UR::Object::UserOperation;

=pod

=head1 NAME

UserOperation - An operation which can be performed by an application
user on an object or objects of a given class.

=head1 SYNOPSIS

The following perl code defines a UserOperation object of subclass
Query::Results::UserOperation.  This subclass of the UserOperation
class works only with, surprise, Query::Results objects.

  $VAR1 = bless
  (
      {
          name => 'open_in_emacs',

          label => 'Open in Emacs',    
          tooltip => 'Open the selected query results in Emacs.',

          subject_class => 'Query::Results',

          sort_position => 4,

          validity_test_function => sub { 1 },

          execution_function => sub
          {
              my ($self, $results) = @_;        

              # Since the filename is undef, the dump_to_file autogenerates a temp file and returns the name.
              my $filename = $results->dump_to_file(undef, headers => 'ask', tabdelimit => 'ask');

              unless ($filename)
              {
                  App->error_message("Error dumping file.");
                  return 0;
              }

              system "(emacs $filename; rm $filename) &";

              $self->status_message("Emacs window opened.");        
              return 1;
          }        
      },
      'Query::Results::UserOperation'
  );

Adding files with similar text to the correct directory will cause new
UserOperation objects to show themselves in right-click menus, and in
other application which look for UserOperations.  For example, adding
files with similar text to the directory
$PERL_OBJECT_PATH/Query/Results/UserOperation will cause new
Query::Results::UserOperation objects to show themselves in
right-click menus and in other places where application look for
UserOperations for objects they work-with.

=head1 DESCRIPTION

Objects of class UserOperation impliment a specific operation for
objects of an associated class.

Each of these is similar to an object method, and may in-fact simply
wrap a method for a particular class.  UserOperation objects are
distinct from object methods in the following ways:

=over

=item 1.

Methods are available to the programmer, but are not necessarily
available to a user for invocation at will.  UserOperation objects are
available to the user directly, simply by existing and being
associated with a given object class.  Note that they can have
conditional code embedded to limit their availablity to particular
applications, situations, etc.

=item 2.

Methods vary in whether they expect parameters, and what those
parameters are.  UserOperation objects expect only an object or set of
objects of the required class.  Any parameters required by the
operation will have to resolve themselves, often by popping up a
dialog box, prompting the user at the command-line, or better yet,
doing either depending on application context.  (i.e. using the
App::UI generic user interface module)

=back

Often, when a user operation object is constructed, it is a good time
to ask whether a new object method should be constructed, and the user
operation object should be a lightweight wrapper around the method,
possibly providing a user interface to the method's parameters.

Each UserOperation works on a specific class of object, returnable and
settable by the subject_class() method.  In most cases, a derived
class is created for which this value is constant.  For example, user
operations for the Clone object will be of type Clone::UserOperation,
which @ISA UserOperation, but which overrides the class method to
always return 'Clone'.

=cut

# set up package
require 5.6.0;
use warnings;
use strict;
our $VERSION = '0.1';
our (@ISA, @EXPORT, @EXPORT_OK);

# set up module
require Exporter;
@ISA= qw(Exporter DumpedObject UR::ModuleBase);
@EXPORT = qw();
@EXPORT_OK = qw();

use IO::File;
use DumpedObject;
##- use UR::ModuleBase;

=pod

=head1 METHODS

=over 4

=item new($name)

The constructor for a UserOperation object always takes a unique name.
It will check the filesystem for an object of that name, and load it if it exists.
Otherwise a new object will be created with that name.

=item subject_class([$class_name])

Get the name of the class of object which this UserOperation operates upon.

=item label([$text])

Get or set the default label text for a given UserOperation object.

=item tooltip([$text])

Get or set the tooltip text for a given UserOperation object.

=item sort_position([$index])

Get or set the relative sort position this UserOperation should have
relative to other UOs of the same subclass.

=item validity_test_function([\&function])

Get or set the function which determines whether the operation can
occur on a given object.  This function will be passed the object or
objects which may be operated upon as parameters.  Often this code
tests the application name, consults the database, or makes other
checks which ignore the actual object instance(s) passed-in.

=item execution_function([\&function])

Get or set the function which invokes the operation on instance(s) of
the given subject_class.  This function will be passed the object or
objects which are to be operated upon as parameters.

=item validate($object, [$object, ...])

This method calls the validity_test_function for the passed-in
objects, which should be of class subject_class.

=item execute($object, [$object, ...])

This method calls the execution_function for for the passed-in
objects, which should be of class subject_class.

=back

=cut

# sub new() inherited from DumpedObject

sub name { $_[0]->{name} }

sub subject_class 
{
    my $self = shift;
    
    # If set on the object explicitly (rare), return the class name.
    return $self->{subject_class} if (ref($self) and $self->{subject_class});
    
    # Typically, this is a subclass derived from UserOperation, 
    # and whose name is SUBJECT_CLASS::UserOperation.
    my $class = ref($self);
    my ($subject_class) = ($class =~ /(.+)::UserOperation$/);
    
    unless ($subject_class and $subject_class )
    {
        use Data::Dumper;
        die "Unable to determine the subject_class for $class $self.\n" . Dumper($self) . "\n";
    }
}

sub label { $_[0]->{label} }

sub tooltip { $_[0]->{tooltip} }

sub sort_position { $_[0]->{sort_position} }

sub validity_test_function { $_[0]->{validity_test_function} }

sub execution_function { $_[0]->{execution_function}; }

sub validate { my $self = shift; $self->validity_test_function->($self,@_); }

sub execute { my $self = shift; print STDOUT "executing\n"; $self->execution_function->($self,@_); print STDOUT "done\n"; }

1;
__END__

=pod

=head1 BUGS

=over 4

=item *

Objects must be manually created as shown in the synopsis and saved on
the filesystem.  The methods to not support creation within the
application.  (ie "get" works but "set" does not where the
documentation says "get or set".)

=item *

The error handling structure is not complete.  This class will
probably inherit from App, and do $self->error_message when errors
occur, etc.

=back

Report bugs to <ssmith@watson.wustl.edu>.

=head1 AUTHOR

Scott Smith <ssmith@watson.wustl.edu>

=cut

#$Header$
