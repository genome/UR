package Command;

use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use Getopt::Long;
use Term::ANSIColor;

use UR::Object::Type;

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is_abstract => 1,
    has => [
        bare_args   => { is => 'ARRAY', is_optional => 1 },
    ]
);

#
# Standard external interface for two-line wrappers
#

sub execute_with_shell_params_and_exit
{
    # This automatically parses command-line options and "does the right thing":
    my $class = shift;
    
    if (@_) {
        die
qq|
No params expected for execute_with_shell_params_and_exit().
Usage:

#!/usr/bin/env perl
use My::Command;
My::Command->execute_with_shell_params_and_exit;
|;
    }

    my @argv = @ARGV;
    @ARGV = ();
    my $exit_code = $class->_execute_with_shell_params_and_return_exit_code(@argv);
    UR::Context->commit;
    exit $exit_code;
}

sub _execute_with_shell_params_and_return_exit_code
{
    my $class = shift;
    my @argv = @_;

    # make --foo=bar equivalent to --foo bar
    @argv = map {split /=/, $_} @argv; 

    $DB::single = 1;
    my ($delegate_class, $params) = $class->resolve_class_and_params_for_argv(@argv);

    unless ($delegate_class) {
        $class->usage_message($class->help_usage_complete_text);
        return 1;
    }
    
    if (!$params or $params->{help}) {
        $delegate_class->usage_message($delegate_class->help_usage_complete_text,"\n");
        return 1;
    }

    $delegate_class->dump_status_messages(1);
    $delegate_class->dump_warning_messages(1);
    $delegate_class->dump_error_messages(1);
    $delegate_class->dump_debug_messages(0);

    my $command_object = $delegate_class->create(%$params);

    unless ($command_object) {
        # The delegate class should have emitted an error message.
        # This is just in case the developer is sloppy, and the user will think the task did not fail.
        print STDERR "Exiting.\n";
        return 1;;
    }

    $command_object->dump_status_messages(1);
    $command_object->dump_warning_messages(1);
    $command_object->dump_error_messages(1);
    $command_object->dump_debug_messages(0);

    $DB::single = 1;
    
    if (my @problems = $command_object->invalid) {
        $class->usage_message($delegate_class->help_usage_complete_text);
        for my $problem (@problems) {
            $command_object->error_message($problem->desc);
        }
        $command_object->delete();
        return 1;
    }
 
    my $rv = $command_object->execute($params);

    my $exit_code = $delegate_class->exit_code_for_return_value($rv);
    return $exit_code;
}

#
# Standard programmatic interface
# 

sub create 
{
    my $class = shift;
    my ($rule,%extra) = $class->get_rule_for_params(@_);
    if (%extra) {
        $extra{bare_args} = delete $extra{" "};
    }
    my $self = $class->SUPER::create($rule->params_list, %extra);
    return unless $self;

    # set non-optional boolean flags to false.
    for my $property_meta ($self->_shell_args_property_meta) {
        my $property_name = $property_meta->property_name;
        if (!$property_meta->is_optional and !defined($self->$property_name)) {
            if ($property_meta->data_type =~ /Boolean/i) {
                $self->$property_name(0);
            }
        }
    }    
    
    return $self;
}

#
# Methods to override in concrete subclasses.
#

sub execute 
{    
    my $self = shift;
    my $class = ref($self) || $self;
    if ($class eq __PACKAGE__) {
        die "The execute() method is not defined for $_[0]!";
    }
    return 1;
}

# Translates a true/false value from the command module's execute()
# from Perl (where positive means success), to shell (where 0 means success)
# Also, execute() could return a negative value; this is converted to
# positive and used as the shell exit code.  NOTE: This means execute()
# returning 0 and -1 mean the same thing
sub exit_code_for_return_value 
{
    my $self = shift;
    my $return_value = shift;
    if (! $return_value) {
        $return_value = 1;
    } elsif ($return_value < 0) {
        $return_value = 0 - $return_value;
    } else {
        $return_value = 0 
    }
    return $return_value;
}

sub help_brief 
{
    my $self = shift;
    if ($self->is_sub_command_delegator) {
        my @names = $self->sub_command_names;
        if (@names) {
            return ""
        }
        else {
            return "no sub-commands implemented!"
        }
    }
    return "!!! define help_brief() in module $self!";
}

sub help_bare_args
{
    return ''
}

sub help_synopsis 
{
    my $self = shift;
    return;
}

sub help_detail 
{
    my $self = shift;
    return "!!! define help_detail() in module " . ref($self) || $self . "!";
}

sub sub_command_sort_position 
{ 
    # override to do something besides alpha sorting by name
    shift->command_name
}


#
# Self reflection
#

sub is_abstract 
{
    # Override when writing an subclass which is also abstract.
    my $self = shift;
    my $class_meta = $self->get_class_object;
    return $class_meta->is_abstract;
}

sub is_executable 
{
    my $self = shift;
    if ($self->can("execute") eq __PACKAGE__->can("execute")) {
        return;
    }
    elsif ($self->is_abstract) {
        return;
    }
    else {
        return 1;
    }
}

sub is_sub_command_delegator
{
    my $self = shift;
    if (scalar($self->sub_command_dirs)) {
        return 1;
    }
    else {
        return;
    }
}

sub _time_now 
{
    # return the current time in context
    # this may not be the real time in selected cases
    UR::Time->now;    
}

sub command_name 
{
    my $self = shift;
    my $class = ref($self) || $self;
    my @words;
    if ( my ($base,$ext) = $class->_base_command_class_and_extension() ) {
        $ext = $class->_command_name_for_class_word($ext);
        unless ($base->can("command_name")) {
            local $SIG{__DIE__};
            eval "use $base";
        }
        if ($base->can("command_name")) {
            return $base->command_name . " " . $ext;
        }
        elsif ($ext eq "command") {
            return $base;
        }
        else {
            return $base . " " . $ext;
        }
    }
    else {
        return $class;
    }
}

sub color_command_name 
{
    my $text = shift;
    
    my $colored_text = [];

    my @COLOR_TEMPLATES = ('red', 'bold red', 'magenta', 'bold magenta');
    my @parts = split(/\s+/, $text);
    for(my $i = 0 ; $i < @parts ; $i++ ){
        push @$colored_text, ($i < @COLOR_TEMPLATES) ? Term::ANSIColor::colored($parts[$i], $COLOR_TEMPLATES[$i]) : $parts[$i];
    }
    
    return join(' ', @$colored_text);
}

sub _base_command_class_and_extension 
{
    my $self = shift;
    my $class = ref($self) || $self;
    return ($class =~ /^(.*)::([^\:]+)$/); 
}

sub _command_name_for_class_word 
{
    my $self = shift;
    my $s = shift;
    $s =~ s/_/-/g;
    $s =~ s/([a-z])([A-Z])/$1-$2/g;
    $s = lc($s);
    return $s;
}

sub command_name_brief
{
    my $self = shift;
    my $class = ref($self) || $self;
    my @words;
    if ( my ($base,$ext) = $class->_base_command_class_and_extension() ) {
        $ext = $class->_command_name_for_class_word($ext);
        return $ext;
    }
    else {
        return $self->command_name;
    }
}

#
# Methods to transform shell args into command properties
#

sub resolve_class_and_params_for_argv
{
    # This is used by execute_with_shell_params_and_exit, but might be used within an application.
    my $self = shift;
    my @argv = @_;

    if ($self->is_sub_command_delegator) {

        if (my $class_for_sub_command = ($argv[0] ? $self->class_for_sub_command($argv[0]) : undef)) {
            # delegate
            shift @argv;
            return $class_for_sub_command->resolve_class_and_params_for_argv(@argv);
        }
        
        if ($self->is_executable and @argv) {
            # this has sub-commands, and is also executable
            # fall through to the execution_logic...
        }
        else {
            #$self->error_message(
            #    'Bad command "' . $sub_command . '"'
            #    , "\ncommands:"
            #    , $self->help_sub_commands
            #);
            return ($self,undef);
        }
    }
    
    my %params;

    my @spec = $self->_shell_args_getopt_specification;
    unless (grep { /^help\W/ } @spec) {
        push @spec, "help!";
    }

    # Thes nasty GetOptions modules insist on working on
    # the real @ARGV, while we like a little moe flexibility.
    # Not a problem in Perl. :)

    local $SIG{__WARN__} = \&UR::Util::null_sub;

    local @ARGV;
    @ARGV = @argv;
    
    unless (GetOptions(\%params,@spec)) {
        my @failed = grep { /^--/ } grep { /\W*(\w+)/; not exists $params{$1} } @argv;
        $self->error_message("Bad params! @failed");
        return($self, undef);
    }

    # Is there a standard getopt spec for capturing non-option paramters?
    # Perhaps that's not getting "options" :)

    $params{" "} = [@ARGV];

    for my $key (keys %params) {
        next unless $key =~ /-/;
        my $new_key = $key;
        $new_key =~ s/\-/_/g;
        $params{$new_key} = delete $params{$key};
    }

    return $self, \%params;
}

#
# Methods which let the command auto-document itself.
#

sub help_usage_complete_text
{
    my $self = shift;

    my $command_name = $self->command_name;
    my $text;
    
    if (not $self->is_executable) {
        # no execute implemented
        if ($self->is_sub_command_delegator) {
            # show the list of sub-commands
            $text = "commands:\n" . $self->help_sub_commands;
        }
        else {
            # developer error
            my (@sub_command_dirs) = $self->sub_command_dirs;
            if (grep { -d $_ } @sub_command_dirs) {
                $text .= "No execute() implemented in $self, and no sub-commands found!"
            }
            else {
                $text .= "No execute() implemented in $self, and no directory of sub-commands found!"
            }
        }
    }
    else {
        # standard: update this to do the old --help format
        my $synopsis = $self->help_synopsis;
        my $required_args = $self->help_options(is_optional => 0);
        my $optional_args = $self->help_options(is_optional => 1);
        my $sub_commands = $self->help_sub_commands(brief => 1) if $self->is_sub_command_delegator;
        $text =
            "\n   "
            .   $self->command_name . " " . $self->_shell_args_usage_string . "\n\n"
            .   (
                    $synopsis 
                    ? "SYNOPSIS:\n\n" . $synopsis . "\n\n"
                    : ''
                )
            .   (
                    $required_args
                    ? "REQUIRED ARGUMENTS:\n\n" . $required_args . "\n\n"
                    : ''
                )
            .   (
                    $optional_args
                    ? "OPTIONAL ARGUMENTS:\n\n" . $optional_args . "\n\n"
                    : ''
                )
            . "DESCRIPTION:\n\n"
            .   $self->help_detail
            . "\n"
            .   (
                    $sub_commands
                    ? "SUB-COMMANDS:\n\n" . $sub_commands . "\n\n"
                    : ''
                );
    }
    return "\n$text";
}

sub help_usage_command_pod
{
    my $self = shift;

    my $command_name = $self->command_name;
    my $pod;
    
    if (not $self->is_executable) {
        # no execute implemented
        if ($self->is_sub_command_delegator) {
            # show the list of sub-commands
            $pod = "commands:\n" . $self->help_sub_commands;
        }
        else {
            # developer error
            my (@sub_command_dirs) = $self->sub_command_dirs;
            if (grep { -d $_ } @sub_command_dirs) {
                $pod .= "No execute() implemented in $self, and no sub-commands found!"
            }
            else {
                $pod .= "No execute() implemented in $self, and no directory of sub-commands found!"
            }
        }
    }
    else {
        # standard: update this to do the old --help format
        my $synopsis = $self->command_name . ' ' . $self->_shell_args_usage_string . "\n\n" . $self->help_synopsis;
        my $required_args = $self->help_options(is_optional => 0, format => "pod");
        my $optional_args = $self->help_options(is_optional => 1, format => "pod");
        my $sub_commands = $self->help_sub_commands(brief => 1) if $self->is_sub_command_delegator;
        $pod =
            "\n=pod"
            . "\n\n=head1 NAME"
            .  "\n\n"
            .   $self->command_name . " - " . $self->help_brief . "\n\n"
            .   (
                    $synopsis 
                    ? "=head1 SYNOPSIS\n\n" . $synopsis . "\n\n"
                    : ''
                )
            .   (
                    $required_args
                    ? "=head1 REQUIRED ARGUMENTS\n\n" . $required_args . "\n\n"
                    : ''
                )
            .   (
                    $optional_args
                    ? "=head1 OPTIONAL ARGUMENTS\n\n" . $optional_args . "\n\n"
                    : ''
                )
            . "=head1 DESCRIPTION:\n\n"
            . join('', map { "  $_\n" } split ("\n",$self->help_detail))
            . "\n"
            .   (
                    $sub_commands
                    ? "=head1 SUB-COMMANDS\n\n" . $sub_commands . "\n\n"
                    : ''
                )
            . "\n\n=cut\n\n";
    }
    return "\n$pod";
}

sub help_header
{
    my $class = shift;
    return sprintf("%s - %-80s\n",
        $class->command_name
        ,$class->help_brief
    )
}

sub help_options
{
    my $self = shift;
    my %params = @_;

    my $format = delete $params{format};
    my @property_meta = $self->_shell_args_property_meta(%params);

    my @data;
    my $max_name_length = 0;
    for my $property_meta (@property_meta) {
        my $param_name = $self->_shell_arg_name_from_property_meta($property_meta);
        $param_name = "--$param_name";
        my $doc = $property_meta->doc;
        unless ($doc) {
            $doc = "undocumented";
        }
        $max_name_length = length($param_name) if $max_name_length < length($param_name);
        push @data, [$param_name, $doc];
    }
    my $text = '';
    for my $row (@data) {
        if (defined($format) and $format eq 'pod') {
            $text .= "\n=item " . $row->[0] . "\n  " . $row->[1] . "\n"; 
        }
        else {
            $text .= $row->[0];
            $text .= ' ' x ($max_name_length - length($row->[0]));
            $text .= '    ' . $row->[1];
            $text .= "\n"; 
        }
    }

    return $text;
}

sub help_sub_commands
{
    my $class = shift;
    my %params = @_;
    my $command_name_method = ($params{brief} ? 'command_name_brief' : 'command_name');
    
    $DB::single=1;
    my @sub_command_classes = $class->sub_command_classes;
    no warnings;
    my @data =  
        map {
            [
                color_command_name($_->$command_name_method),
                Term::ANSIColor::colored($_->_shell_args_usage_string_abbreviated, 'cyan'),
                Term::ANSIColor::colored(ucfirst($_->help_brief), 'blue'),
            ];
        }
        sort {
            ($a->sub_command_sort_position <=> $b->sub_command_sort_position)
            || 
            ($a->sub_command_sort_position cmp $b->sub_command_sort_position) 
        }
        grep { not $_->is_abstract }
        @sub_command_classes
    ;
    
    my @max_width = (0,0,0);
    for (@data) {
        for my $c (0..2) {
            $max_width[$c] = length($_->[$c]) if $max_width[$c] < length($_->[$c]);
        }
    }
    my $text = '';
    for my $row (@data) {
        for my $c (0..2) {
            $text .= '  ';
            $text .= $row->[$c];
            $text .= ' ';
            $text .= ' ' x ($max_width[$c]-length($row->[$c]));
        }
        $text .= "\n";
    }
    return $text;
}

#
# Methods which transform command properties into shell args (getopt)
#

sub _shell_args_property_meta
{
    my $self = shift;
    my $class_meta = $self->get_class_object;
    my @property_meta = sort { $a->property_name cmp $b->property_name } $class_meta->get_all_property_objects(@_);
    my @result;
    for my $property_meta (@property_meta) {
        my $property_name = $property_meta->property_name;
        next if $property_name eq 'id';
        next if $property_name =~ /^_/;
        next if $property_name eq 'bare_args';
        next if defined($property_meta->data_type) and $property_meta->data_type =~ /::/;
        push @result, $property_meta;    
    }
    return @result;
}

sub _shell_arg_name_from_property_meta
{
    my ($self, $property_meta) = @_;
    my $property_name = $property_meta->property_name;
    my $param_name = $property_name;
    $param_name =~ s/_/-/g;
    return $param_name; 
}

sub _shell_arg_getopt_qualifier_from_property_meta
{
    my ($self, $property_meta) = @_;
    if (defined($property_meta->data_type) and $property_meta->data_type =~ /Boolean/) {
        return '!';
    }
    else {
        return '=s';
    }
}

sub _shell_arg_usage_string_from_property_meta 
{
    my ($self, $property_meta) = @_;
    my $string = $self->_shell_arg_name_from_property_meta($property_meta);
    $string = "--$string";
    if (defined($property_meta->data_type) and $property_meta->data_type =~ /Boolean/) {
        $string = "[$string]";
    }
    else {
        $string .= '=?'; 
        if ($property_meta->is_optional) {
            $string = "[$string]";
        }
    }
    return $string;
}

sub _shell_args_getopt_specification 
{
    my $self = shift;
    my @getopt =
        sort 
        map { 
            $self->_shell_arg_name_from_property_meta($_)
            .
            $self->_shell_arg_getopt_qualifier_from_property_meta($_)
        }
        $self->_shell_args_property_meta;
    return @getopt; 
}

sub _shell_args_usage_string
{
    my $self = shift;
    if ($self->is_executable) {
        return join(
            " ", 
            map { 
                $self->_shell_arg_usage_string_from_property_meta($_) 
            } $self->_shell_args_property_meta()
            
        );
    }
    elsif ($self->is_sub_command_delegator) {
        my @names = $self->sub_command_names;
        return "[" . join("|",@names) . "] ..."
    }
    else {
        return "(no execute or sub commands implemented)"
    }
    return "";
}

sub _shell_args_usage_string_abbreviated
{
    my $self = shift;
    my $detailed = $self->_shell_args_usage_string;
    if (length($detailed) < 40) {
        return $detailed;
    }
    elsif ($self->is_sub_command_delegator) {
        return "...";
    }
    else {
        return "ARGS";
    }
}

#
# The following methods build allow a command to determine its 
# sub-commands, if there are any.
#

# This is for cases in which the Foo::Bar command delegates to
# Foo::Bar::Baz, Foo::Bar::Buz or Foo::Bar::Doh, depending on its paramters.

sub sub_command_dirs
{
    my $class = shift;
    my $module = ref($class) || $class;
    $module =~ s/::/\//g;
    
    # multiple dirs is not working quite yet
    #my @paths = grep { -d $_ } map { "$_/$module"  } @INC; 
    #return @paths;

    $module .= '.pm';
    my $path = $INC{$module};
    unless ($path) {
        print Data::Dumper::Dumper("no $module in \%INC: ", \%INC);
        return;
    }
    $path =~ s/.pm$//;
    unless (-d $path) {
        return;
    }
    return $path;
}

sub sub_command_classes
{
    $DB::single=1;
    my $class = shift;
    my @paths = $class->sub_command_dirs;
    return unless @paths;
    @paths = grep { s/\.pm$// } map { glob("$_/*") } @paths;
    return unless @paths;
    my @classes =
        map { $class->class_for_sub_command($_) }
        map { s/_/-/g; $_ }
        map { basename($_) }
        @paths;
    return @classes;
}

sub sub_command_names
{
    my $class = shift;
    my @sub_command_classes = $class->sub_command_classes;
    my @sub_command_names= map { $_->command_name_brief } @sub_command_classes;
    return @sub_command_names;
}

sub class_for_sub_command
{
    my $self = shift;
    my $class = ref($self) || $self;
    my $sub_command = shift;

    my $sub_class = join("", map { ucfirst($_) } split(/-/, $sub_command));
    $sub_class = $class . "::" . $sub_class;

    eval "use $sub_class;";
    if ($@) {
        if ($@ =~ /^Can't locate .*\.pm in \@INC/) {
            #die "Failed to find $sub_class! $class_for_sub_command.pm!\n$@";
            return;
        }
        else {
            my @msg = split("\n",$@);
            pop @msg;
            pop @msg;
            $self->error_message("$sub_class failed to compile!:\n@msg\n\n");
            return;
        }
    }
    elsif (my $isa = $sub_class->isa("Command")) {
        if (ref($isa)) {
            # dumb modules (Test::Class) mess with the standard isa() API
            if ($sub_class->SUPER::isa("Command")) {
                return $sub_class;
            }
            else {
                return;
            }
        }
        return $sub_class;
    }
    else {
        return;
    }
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

for my $type (qw/error warning status debug usage/) {

    for my $method_base (qw/_messages_callback queue_ dump_/) {
        my $method = (substr($method_base,0,1) eq "_"
            ? $type . $method_base
            : $method_base . $type . "_messages"
        );
        my $method_subref = sub {
            my $self = shift;

            my $msgdata;
            if (ref($self)) {
                $msgdata = $self->{msgdata} ||= {};
            }
            else {
                no strict 'refs';
                $msgdata = ${ $self . "::msgdata" } ||= {};
            }

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

        my $msgdata;
        if (ref($self)) {
            $msgdata = $self->{msgdata} ||= {};
        }
        else {
            no strict 'refs';
            $msgdata = ${ $self . "::msgdata" } ||= {};
        }

        if (@_) {
            my $msg = shift;
            chomp $msg if defined $msg;

            unless (defined ($msgdata->{'dump_' . $type . '_messages'})) {
                $msgdata->{'dump_' . $type . '_messages'} = $type eq "status" ? 0 : 1;
            }

            if (my $code = $msgdata->{ $type . "_messages_callback"}) {
                $code->($self,$msg);
            }
            if ($msgdata->{ "dump_" . $type . "_messages" }) {
                print $stderr ($type eq "status" ? () : (uc($type), ": ")), (defined($msg) ? $msg : ""), "\n";
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

        my $msgdata;
        if (ref($self)) {
            $msgdata = $self->{msgdata} ||= {};
        }
        else {
            no strict 'refs';
            $msgdata = ${ $self . "::msgdata" } ||= {};
        }

        return $msgdata->{$type . "_messages_arrayref"};
    };


    my $array_subname = $type . "_messages";
    my $array_subref = sub {
        my $self = shift;

        my $msgdata;
        if (ref($self)) {
            $msgdata = $self->{msgdata} ||= {};
        }
        else {
            no strict 'refs';
            $msgdata = ${ $self . "::msgdata" } ||= {};
        }

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

