package Command::V2;

use strict;
use warnings;

use UR;
use Data::Dumper;
use File::Basename;
use Getopt::Long;

use Command::View::DocMethods;
use Command::Dispatch::Shell;

our $VERSION = "0.30"; # UR $VERSION;

our $entry_point_class;
our $entry_point_bin;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'Command',
    is_abstract => 1,
    attributes_have => [
        is_param            => { is => 'Boolean', is_optional => 1 },        
        is_input            => { is => 'Boolean', is_optional => 1 },
        is_output           => { is => 'Boolean', is_optional => 1 },
        shell_args_position => { is => 'Integer', is_optional => 1, 
                                doc => 'when set, this property is a positional argument when run from a shell' },
        completion_handler  => { is => 'MethodName', is_optional => 1,
                                doc => 'to supply auto-completions for this parameter, call this class method' },
        require_user_verify => { is => 'Boolean', is_optional => 1,
                                doc => 'when expanding user supplied values: 0 = never verify, 1 = always verify, undef = determine automatically', },        
    ],
    has_optional => [
        is_executed => { is => 'Boolean' },
        result      => { is => 'Scalar', is_output => 1 },
    ],
);

sub _is_hidden_in_docs { return; }

sub _init_subclass {
    # Each Command subclass has an automatic wrapper around execute().
    # This ensures it can be called as a class or instance method, 
    # and that proper handling occurs around it.
    my $subclass_name = $_[0];
    no strict;
    no warnings;
    if ($subclass_name->can('execute')) {
        # NOTE: manipulating %{ $subclass_name . '::' } directly causes ptkdb to segfault perl
        my $new_symbol = "${subclass_name}::_execute_body";
        my $old_symbol = "${subclass_name}::execute";
        *$new_symbol = *$old_symbol;
        undef *$old_symbol;
    }
    else {
        #print "no execute in $subclass_name\n";
    }
    return 1;
}

sub create {
    my $class = shift;
    my ($rule,%extra) = $class->define_boolexpr(@_);
    my @params_list = $rule->params_list;
    my $self = $class->SUPER::create(@params_list, %extra);
    return unless $self;

    # set non-optional boolean flags to false.
    for my $property_meta ($self->_shell_args_property_meta) {
        my $property_name = $property_meta->property_name;
        if (!$property_meta->is_optional and !defined($self->$property_name)) {
            if (defined $property_meta->data_type and $property_meta->data_type =~ /Boolean/i) {
                $self->$property_name(0);
            }
        }
    }    
    
    return $self;
}

sub __errors__ {
    my ($self,@property_names) = @_;
    return ($self->SUPER::__errors__);
}


sub execute {
    # This is a wrapper for real execute() calls.
    # All execute() methods are turned into _execute_body at class init, 
    # so this will get direct control when execute() is called. 
    my $self = shift;

    #TODO handle calls to SUPER::execute() from another execute().    

    # handle calls as a class method
    my $was_called_as_class_method = 0;
    if (ref($self)) {
        if ($self->is_executed) {
            Carp::confess("Attempt to re-execute an already executed command.");
        }
    }
    else {
        # called as class method
        # auto-create an instance and execute it
        $self = $self->create(@_);
        return unless $self;
        $was_called_as_class_method = 1;
    }

    # handle __errors__ objects before execute
    if (my @problems = $self->__errors__) {
        for my $problem (@problems) {
            my @properties = $problem->properties;
            $self->error_message("Property " .
                                 join(',', map { "'$_'" } @properties) .
                                 ': ' . $problem->desc);
        }
        $self->delete() if $was_called_as_class_method;
        return;
    }

    my $result = $self->_execute_body(@_);

    $self->is_executed(1);
    $self->result($result);

    return $self if $was_called_as_class_method;
    return $result;
}

sub _execute_body {    
    # default implementation in the base class

    # Override "execute" or "_execute_body" to implement the body of the command.
    # See above for details of internal implementation.

    my $self = shift;
    my $class = ref($self) || $self;
    if ($class eq __PACKAGE__) {
        die "The execute() method is not defined for $_[0]!";
    }
    return 1;
}


sub exit_code_for_return_value {
    my $self = shift;
    my $return_value = shift;

    # Translates a true/false value from the command module's execute()
    # from Perl (where positive means success), to shell (where 0 means success)
    # Also, execute() could return a negative value; this is converted to
    # positive and used as the shell exit code.  NOTE: This means execute()
    # returning 0 and -1 mean the same thing

    if (! $return_value) {
        $return_value = 1;
    } elsif ($return_value < 0) {
        $return_value = 0 - $return_value;
    } else {
        $return_value = 0 
    }
    return $return_value;
}


#
# Implement error_mesage/warning_message/status_message in a way
# which handles command-specific callbacks.
#


# Build a set of methods for getting/setting/printing error/warning/status messages
# $class->dump_error_messages(<bool>) Turn on/off printing the messages to STDERR
#     error and warnings default to on, status messages default to off
# $class->queue_error_messages(<bool>) Turn on/off queueing of messages
#     defaults to off
# $class->error_message("blah"): set an error message
# $class->error_message() return the last message
# $class->error_messages()  return all the messages that have been queued up
# $class->error_messages_arrayref()  return the reference to the underlying
#     list messages get queued to.  This is the method for truncating the list
#     or altering already queued messages
# $class->error_messages_callback(<subref>)  Specify a callback for when error
#     messages are set.  The callback runs before printing or queueing, so
#     you can alter @_ and change the message that gets printed or queued
# And then the same thing for status and warning messages

# The filehandle to print these messages to.  In normal operation this'll just be
# STDERR, but the test case can change it to capture the messages to somewhere else

our $stderr = \*STDERR;
our $stdout = \*STDOUT;

our %msgdata;

sub _get_msgdata {
    my $self = $_[0];
    
    if (ref($self)) {
        no strict 'refs';
        my $object_msgdata = $msgdata{$self->id} ||= {};
        my $class_msgdata = ref($self)->_get_msgdata;

        while (my ($k,$v) = each(%$class_msgdata)) {
            $object_msgdata->{$k} = $v unless (exists $object_msgdata->{$k});
        }

        return $object_msgdata;
    }
    else {
        no strict 'refs';
        return ${ $self . "::msgdata" } ||= {};
    }
}

for my $type (qw/error warning status debug usage/) {

    for my $method_base (qw/_messages_callback queue_ dump_/) {
        my $method = (substr($method_base,0,1) eq "_"
            ? $type . $method_base
            : $method_base . $type . "_messages"
        );
        my $method_subref = sub {
            my $self = shift;
            my $msgdata = $self->_get_msgdata;
            $msgdata->{$method} = pop if @_;
            return $msgdata->{$method};
        };
        no strict;
        no warnings;
        *$method = $method_subref;
    }

    my $logger_subname = $type . "_message";
    my $logger_subref = sub {
        my $self = shift;

        my $msgdata = $self->_get_msgdata();

        if (@_) {
            my $msg = shift;
            chomp $msg if defined $msg;

            unless (defined ($msgdata->{'dump_' . $type . '_messages'})) {
                $msgdata->{'dump_' . $type . '_messages'} = $type eq "status" ? (exists $ENV{'UR_COMMAND_DUMP_STATUS_MESSAGES'} && $ENV{'UR_COMMAND_DUMP_STATUS_MESSAGES'} ? 1 : 0) : 1;
            }

            if (my $code = $msgdata->{ $type . "_messages_callback"}) {
                $code->($self,$msg);
            }
            if (my $fh = $msgdata->{ "dump_" . $type . "_messages" }) {
                if ( $type eq 'usage' ) {
                    (ref($fh) ? $fh : $stdout)->print((($type eq "status" or $type eq 'usage') ? () : (uc($type), ": ")), (defined($msg) ? $msg : ""), "\n");
                }
                else {
                    (ref($fh) ? $fh : $stderr)->print((($type eq "status" or $type eq 'usage') ? () : (uc($type), ": ")), (defined($msg) ? $msg : ""), "\n");
                }
            }
            if ($msgdata->{ "queue_" . $type . "_messages"}) {
                my $a = $msgdata->{ $type . "_messages_arrayref" } ||= [];
                push @$a, $msg;
            }
            $msgdata->{ $type . "_message" } = $msg;
        }
        $msgdata->{ $type . "_message" };
    };


    my $arrayref_subname = $type . "_messages_arrayref";
    my $arrayref_subref = sub {
        my $self = shift;
        my $msgdata = $self->_get_msgdata;
        return $msgdata->{$type . "_messages_arrayref"};
    };


    my $array_subname = $type . "_messages";
    my $array_subref = sub {
        my $self = shift;

        my $msgdata = $self->_get_msgdata;
        return ref($msgdata->{$type . "_messages_arrayref"}) ?
               @{ $msgdata->{$type . "_messages_arrayref"} } :
               ();
    };

    no strict;
    no warnings;

    *$logger_subname    = $logger_subref;
    *$arrayref_subname  = $arrayref_subref;
    *$array_subname     = $array_subref;
}



1;

__END__

=pod

=head1 NAME

Command - base class for modules implementing the command pattern

=head1 SYNOPSIS

  use TopLevelNamespace;

  class TopLevelNamespace::SomeObj::Command {
    is => 'Command',
    has => [
        someobj => { is => 'TopLevelNamespace::SomeObj', id_by => 'some_obj_id' },
        verbose => { is => 'Boolean', is_optional => 1 },
    ],
  };

  sub execute {
      my $self = shift;
      if ($self->verbose) {
          print "Working on id ",$self->some_obj_id,"\n";
      }
      my $result = $someobj->do_something();
      if ($self->verbose) {
          print "Result was $result\n";
      }
      return $result;
  }

  sub help_brief {
      return 'Call do_something on a SomeObj instance';
  }
  sub help_synopsis {
      return 'cmd --some_obj_id 123 --verbose';
  }
  sub help_detail {
      return 'This command performs a FooBarBaz transform on a SomObj object instance by calling its do_something method.';
  }

  # Another part of the code
 
  my $cmd = TopLevelNamespace::SomeObj::Command->create(some_obj_id => $some_obj->id);
  $cmd->execute();

=head1 DESCRIPTION

The Command module is a base class for creating other command modules
implementing the Command Pattern.  These modules can be easily reused in
applications or loaded and executed dynamicaly in a command-line program.

Each Command subclass represents a reusable work unit.  The bulk of the
module's code will likely be in the execute() method.  execute() will
usually take only a single argument, an instance of the Command subclass.

=head1 Command-line use

Creating a top-level Command module called, say TopLevelNamespace::Command,
and a script called tln_cmd that looks like:

  #!/usr/bin/perl
  use TopLevelNamespace;
  TopLevelNamespace::Command->execute_with_shell_params_and_exit();

gives you an instant command-line tool as an interface to the hierarchy of
command modules at TopLevelNamespace::Command.  

For example:

  > tln_cmd foo bar --baz 1 --qux

will create an instance of TopLevelNamespace::Command::Foo::Bar (if that
class exists) with params baz => 1 and qux => 1, assumming qux is a boolean
property, call execute() on it, and translate the return value from execute()
into the appropriate notion of a shell return value, meaning that if
execute() returns true in the Perl sense, then the script returns 0 - true in
the shell sense.

The infrastructure takes care of turning the command line parameters into
parameters for create().  Params designated as is_optional are, of course,
optional and non-optional parameters that are missing will generate an error.

--help is an implicit param applicable to all Command modules.  It generates 
some hopefully useful text based on the documentation in the class definition
(the 'doc' attributes you can attach to a class and properties), and the
strings returned by help_detail(), help_brief() and help_synopsis().

=head1 TODO

This documentation needs to be fleshed out more.  There's a lot of special 
things you can do with Command modules that isn't mentioned here yet.

=cut



