package Command;

use strict;
use warnings;

use UR;
use Data::Dumper;
use File::Basename;
use Getopt::Long;
use Term::ANSIColor;
require Text::Wrap;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is_abstract => 1,
    attributes_have => [
        is_input            => { is => 'Boolean', is_optional => 1 },
        is_output           => { is => 'Boolean', is_optional => 1 },
        is_param            => { is => 'Boolean', is_optional => 1 },
        shell_args_position => { is => 'Integer', is_optional => 1, 
                                 doc => 'when set, this property is a positional argument when run from a shell' },
    ],
    has_optional => [
        # use the above shell_args_position to map to named args instead
        bare_args   => { is => 'ARRAY', is_deprecated => 1 },
        
        is_executed => { is => 'Boolean' },
        
        result      => { is => 'Scalar', is_output => 1 },
    ],
);

# This is changed with "local" where used in some places
$Text::Wrap::columns = 100;

# Required for color output
eval {
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";
};

sub import {
    my $class = $_[0];
    if ($ENV{GETOPT_COMPLETE_CACHE}) {
        # This environment variable is used to interrogate the module
        # when building a cache of options.
        our @OPTS_SPEC = $class->resolve_option_completion_spec();
    }
    shift->SUPER::import(@_);
}

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
        $self->usage_message($self->help_usage_complete_text);
        #print $self->help_usage_complete_text;
        for my $problem (@problems) {
            $self->error_message($problem->desc);
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

sub _execute_body
{    
    # default implementation in the base class
    my $self = shift;
    my $class = ref($self) || $self;
    if ($class eq __PACKAGE__) {
        die "The execute() method is not defined for $_[0]!";
    }
    return 1;
}


#
# Standard external interface for shell dispatchers 
#

# TODO: abstract out all dispatchers for commands into a given API
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

    if ($ENV{COMP_LINE}) {
        require Getopt::Complete;
        my @spec = $class->resolve_option_completion_spec();
        my $options = Getopt::Complete::Options->new(@spec);
        $options->handle_shell_completion;
        die "error: failed to exit after handling shell completion!";
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
    @argv = map { ($_ =~ /^(--\w+?)\=(.*)/) ? ($1,$2) : ($_) } @argv;
    my ($delegate_class, $params) = $class->resolve_class_and_params_for_argv(@argv);

    my $rv = $class->_execute_delegate_class_with_params($delegate_class,$params);
    
    my $exit_code = $delegate_class->exit_code_for_return_value($rv);
    return $exit_code;
}

# this is called by both the shell dispatcher and http dispatcher for now
sub _execute_delegate_class_with_params {
    my ($class, $delegate_class, $params) = @_;

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

    my $rv = $command_object->execute($params);

    if ($command_object->__errors__) {
        $command_object->delete;
    }

    return $rv;
}

#
# Standard programmatic interface
# 

sub create 
{
    my $class = shift;
    my ($rule,%extra) = $class->define_boolexpr(@_);
    my $bare_args = delete $extra{" "};
    my @params_list = $rule->params_list;
    my $self = $class->SUPER::create(@params_list, %extra);
    return unless $self;
    $self->bare_args($bare_args) if $bare_args;

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

#
# Methods to override in concrete subclasses.
#

# Override "execute" or "_execute_body" to implement the body of the command.
# See above for details of internal implementation.

# By default, there are no bare arguments.
sub _bare_shell_argument_names { 
    my $self = shift;
    my $meta = $self->__meta__;
    my @ordered_names = 
        map { $_->property_name } 
        sort { $a->{shell_args_position} <=> $b->{shell_args_position} }
        grep { $_->{shell_args_position} }
        $self->_shell_args_property_meta();
    return @ordered_names;
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
    if (my $doc = $self->__meta__->doc) {
        return $doc;
    }
    else {
        my @parents = $self->__meta__->ancestry_class_metas;
        for my $parent (@parents) {
            if (my $doc = $parent->doc) {
                return $doc;
            }
        }
        if ($self->is_sub_command_delegator) {
            my @names = $self->sub_command_names;
            if (@names) {
                return ""
            }
            else {
                return "no sub-commands implemented!"
            }
        }
        else {
            return "no description!!!: define 'doc' in $self";
        }
    }
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
    return '9999999999 ' . $_[0]->command_name_brief;
}


#
# Self reflection
#

sub is_abstract 
{
    # Override when writing an subclass which is also abstract.
    my $self = shift;
    my $class_meta = $self->__meta__;
    return $class_meta->is_abstract;
}

sub is_executable 
{
    my $self = shift;
    if ($self->can("_execute_body") eq __PACKAGE__->can("_execute_body")) {
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
    if ( my ($base,$ext) = $class->_base_command_class_and_extension() ) {
        $ext = $class->_command_name_for_class_word($ext);
        for (1) {
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
                my ($b2,$e2) = _base_command_class_and_extension($base);
                if ($b2) {
                    $ext = $class->_command_name_for_class_word($e2) . ' ' . $ext;
                    $base = $b2;
                    redo;
                }
                else {
                    $base = $class->_command_name_for_class_word($base) . ' ' . $ext;
                    return $base;
                }
            }
        }
    }
    else {
        return lc($base);
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

my $_resolved_params_from_get_options = {};
sub _resolved_params_from_get_options {
    return $_resolved_params_from_get_options;
}

sub resolve_option_completion_spec {
    my ($class,@argv) = @_;
    my @completion_spec;

    # todo: this should not be needed b/c
    # things wanting caching will find the cache data upstream

    my $my_path = $class->__meta__->module_path;
    my $cached_opts_path  = $my_path . '.opts';
    if (-e $cached_opts_path) {
        my $my_mtime = (stat($my_path))[9];
        my $cache_mtime = (stat($cached_opts_path))[9];
        if ($cache_mtime >= $my_mtime) {
            my $content = join('',IO::File->new($cached_opts_path)->getlines);
            no strict;
            no warnings;
            my $data = eval $content;
            @completion_spec = @$data;
            return @completion_spec;
        }
        else {
            warn "\nstale cache, removing $cached_opts_path";
            unlink $cached_opts_path;
        }
    }

    if ($class->is_sub_command_delegator) {
        my @sub = $class->sub_command_names;
        for my $sub (@sub) {
            my $sub_class = $class->class_for_sub_command($sub); 
            my $v =  $sub_class;
            my $sub_tree = \$v; 
            push @completion_spec, '>' . $sub, $sub_tree;
        }
        push @completion_spec, "help!" => undef;
    }
    else {
        my $params_hash;
        ($params_hash,@completion_spec) = $class->_shell_args_getopt_complete_specification;
        no warnings;
        unless (grep { /^help\W/ } @completion_spec) {
            push @completion_spec, "help!" => undef;
        }
    }
    
    # TODO: this should be auto-created by the Getopt::Complete::Cache module
    # when we have some more hooks in place.
    unless (-e $cached_opts_path) {
        eval {
            my $fh = IO::File->new('>' . $cached_opts_path);
            if ($fh) {
                warn "caching options for $class...\n";
                my $src = Data::Dumper::Dumper(\@completion_spec);
                $src =~ s/^\$VAR1/\$${class}::OPTS_SPEC/;
                #print STDERR ">> $src\n";
                $fh->print($src);
            }
        };
    }

    return @completion_spec;
}

sub resolve_class_and_params_for_argv
{
    # This is used by execute_with_shell_params_and_exit, but might be used within an application.
    my $self = shift;
    my @argv = @_;

    if ($self->is_sub_command_delegator) {
        if ( $argv[0] and $argv[0] !~ /^\-/ 
                and my $class_for_sub_command = $self->class_for_sub_command($argv[0]) ) {
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
    
    my ($params_hash,@spec) = $self->_shell_args_getopt_specification;
    unless (grep { /^help\W/ } @spec) {
        push @spec, "help!";
    }

    # Thes nasty GetOptions modules insist on working on
    # the real @ARGV, while we like a little moe flexibility.
    # Not a problem in Perl. :)  (which is probably why it was never fixed)
    local @ARGV;
    @ARGV = @argv;
    
    do {
        # GetOptions also likes to emit warnings instead of return a list of errors :( 
        my @errors;
        local $SIG{__WARN__} = sub { push @errors, @_ };
        
        unless (GetOptions($params_hash,@spec)) {
            for my $error (@errors) {
                $self->error_message($error);
            }
            return($self, undef);
        }
    };

    # Q: Is there a standard getopt spec for capturing non-option paramters?
    # Perhaps that's not getting "options" :)
    # A: Yes.  Use '<>'.  But we need to process this anyway, so it won't help us.

    if (my @names = $self->_bare_shell_argument_names) {
        # for now we only do this for selfes which explicitly implement the method
        # this lets us stay backward compatible with old stuff for now
        for (my $n=0; $n < @ARGV; $n++) {
            my $name = $names[$n];
            unless ($name) {
                $self->error_message("Unexpected bare arguments: @ARGV[$n..$#ARGV]!");
                return($self, undef);
            }
            my $value = $ARGV[$n];
            my $meta = $self->__meta__->property_meta_for_name($name);
            if ($meta->is_many) {
                if ($n == $#names) {
                    # slurp the rest
                    $params_hash->{$name} = [@ARGV[$n..$#ARGV]];
                    last;
                }
                else {
                    die "has-many property $name is not last in bare_shell_argument_names for $self?!";
                }
            }
            else {
                $params_hash->{$name} = $value;
            }
        }
    }



    #TODO when everything is converted to use bare_shell_argument_names, 
    # this should throw an error if there are any @ARGV left.
    $params_hash->{" "} = [@ARGV];

    for my $key (keys %$params_hash) {
        # handle any has-many comma-sep values
        my $value = $params_hash->{$key};
        if (ref($value)) {
            my @new_value;
            for my $v (@$value) {
                my @parts = split(/,\s*/,$v);
                push @new_value, @parts;
            }
            @$value = @new_value;
        }

        # turn dashes into underscores
        next unless $key =~ /-/;
        my $new_key = $key;
        $new_key =~ s/\-/_/g;
        $params_hash->{$new_key} = delete $params_hash->{$key};
    }

    $_resolved_params_from_get_options = $params_hash;

    return $self, $params_hash;
}

#
# Methods which let the command auto-document itself.
#

sub help_usage_complete_text {
    my $self = shift;

    my $command_name = $self->command_name;
    my $text;
    
    if (not $self->is_executable) {
        # no execute implemented
        if ($self->is_sub_command_delegator) {
            # show the list of sub-commands
            $text = sprintf(
                "Commands for %s\n%s",
                Term::ANSIColor::colored($command_name, 'bold'),
                $self->help_sub_commands,
            );
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
        $text = sprintf(
            "\n%s\n%s\n\n%s%s%s%s%s\n",
            Term::ANSIColor::colored('USAGE', 'underline'),
            Text::Wrap::wrap(
                ' ', 
                '    ', 
                Term::ANSIColor::colored($self->command_name, 'bold'),
                $self->_shell_args_usage_string,
            ),
            ( $synopsis 
                ? sprintf("%s\n%s\n", Term::ANSIColor::colored("SYNOPSIS", 'underline'), $synopsis)
                : ''
            ),
            ( $required_args 
                ? sprintf("%s\n%s\n", Term::ANSIColor::colored("REQUIRED ARGUMENTS", 'underline'), $required_args)
                : ''
            ),
            ( $optional_args 
                ? sprintf("%s\n%s\n", Term::ANSIColor::colored("OPTIONAL ARGUMENTS", 'underline'), $optional_args)
                : ''
            ),
            sprintf(
                "%s\n%s\n", 
                Term::ANSIColor::colored("DESCRIPTION", 'underline'), 
                Text::Wrap::wrap(' ', ' ', $self->help_detail)
            ),
            ( $sub_commands 
                ? sprintf("%s\n%s\n", Term::ANSIColor::colored("SUB-COMMANDS", 'underline'), $sub_commands)
                : ''
            ),
        );
    }

    return $text;
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
            $pod = "Commands:\n" . $self->help_sub_commands;
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
                    ? "=head1 REQUIRED ARGUMENTS\n\n=over\n\n" . $required_args . "\n\n=back\n\n"
                    : ''
                )
            .   (
                    $optional_args
                    ? "=head1 OPTIONAL ARGUMENTS\n\n=over\n\n" . $optional_args . "\n\n=back\n\n"
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
        if ($property_meta->{shell_args_position}) {
            $param_name = uc($param_name);
        }

        #$param_name = "--$param_name";
        my $doc = $property_meta->doc;
        my $valid_values = $property_meta->valid_values;
        if (!$doc) {
            if (!$valid_values) {
                $doc = "undocumented";
            }
            else {
                $doc = '';
            }
        }
        if ($valid_values) {
            $doc .= "\nvalid values:\n";
            for my $v (@$valid_values) {
                $doc .= " " . $v . "\n"; 
                $max_name_length = length($v)+2 if $max_name_length < length($v)+2;
            }
            chomp $doc;
        }
        $max_name_length = length($param_name) if $max_name_length < length($param_name);

        my $param_type = $property_meta->data_type;
        if ($param_type !~ m/::/) {
            $param_type = ucfirst(lc($param_type));
        }

        my $default_value = $property_meta->default_value;
        if (defined $default_value) {
            if ($param_type eq 'Boolean') {
                $default_value = $default_value ? "'true'" : "'false' (--no$param_name)";
            } else {
                $default_value = "'$default_value'";
            }
            $default_value = "\nDefault value $default_value if not specified";
        }

        push @data, [$param_name, $param_type, $doc, $default_value];
        if ($param_type eq 'Boolean') {
            push @data, ['no'.$param_name, $param_type, "Make $param_name 'false'" ];
        }
    }
    my $text = '';
    for my $row (@data) {
        if (defined($format) and $format eq 'pod') {
            $text .= "\n=item " . $row->[0] . "\n\n" . $row->[2] . "\n". $row->[3] . "\n";
        }
        elsif (defined($format) and $format eq 'html') {
            $text .= "\n\t<br>" . $row->[0] . "<br> " . $row->[2] . "<br>" . $row->[3]."<br>\n";
        }
        else {
            $text .= sprintf(
                "  %s\n%s\n",
                Term::ANSIColor::colored($row->[0], 'bold') . "   " . $row->[1],
                Text::Wrap::wrap(
                    "    ", # 1st line indent,
                    "    ", # all other lines indent,
                    $row->[2],
                    $row->[3],
                ),
            );
        }
    }

    return $text;
}

sub sorted_sub_command_classes {
    no warnings;
    return sort {
            ($a->sub_command_sort_position <=> $b->sub_command_sort_position)
            ||
            ($a->sub_command_sort_position cmp $b->sub_command_sort_position)
        } 
        shift->sub_command_classes;
}

sub help_sub_commands
{
    my $class = shift;
    my %params = @_;
    my $command_name_method = 'command_name_brief';
    #my $command_name_method = ($params{brief} ? 'command_name_brief' : 'command_name');
    
    my @sub_command_classes = $class->sorted_sub_command_classes;
    no warnings;
    local  $Text::Wrap::columns = 60;
    my @data =
    map {
        my @rows = split("\n",Text::Wrap::wrap('', ' ', $_->help_brief));
        chomp @rows;
        (
            [
            $_->$command_name_method,
            $_->_shell_args_usage_string_abbreviated,
            $rows[0],
            ],
            map { 
                [ 
                '',
                ' ',
                $rows[$_],
                ]
            } (1..$#rows)
        );
    } 
    
    @sub_command_classes;

    $DB::single = 1;
    my @max_width_found = (0,0,0);
    for (@data) {
        for my $c (0..2) {
            $max_width_found[$c] = length($_->[$c]) if $max_width_found[$c] < length($_->[$c]);
        }
    }

    my @colors = (qw/ red   bold /);
    my $text = '';
    for my $row (@data) {
        for my $c (0..2) {
            $text .= '  ';
            $text .= Term::ANSIColor::colored($row->[$c], $colors[$c]),
            $text .= ' ';
            $text .= ' ' x ($max_width_found[$c]-length($row->[$c]));
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
    my $class_meta = $self->__meta__;
    my @property_meta = $class_meta->get_all_property_metas(@_);
    my @result;
    my %seen;
    my (@positional,@required,@optional);
    for my $property_meta (@property_meta) {
        my $property_name = $property_meta->property_name;
        next if $property_name eq 'id';
        next if $property_name eq 'bare_args';
        next if $property_name eq 'result';
        next if $property_name eq 'is_executed';
        next if $property_name =~ /^_/;
        next if defined($property_meta->data_type) and $property_meta->data_type =~ /::/;
        next if not $property_meta->is_mutable;
        next if $property_meta->is_delegated;
        next if $property_meta->is_calculated;
#        next if $property_meta->{is_output}; # TODO: This was breaking the G::M::T::Annotate::TranscriptVariants annotator. This should probably still be here but temporarily roll back
        next if $property_meta->is_transient;
        next if $seen{$property_name};
        $seen{$property_name} = 1;
        next if $property_meta->is_constant;
        if ($property_meta->{shell_args_position}) {
            push @positional, $property_meta;
        }
        elsif ($property_meta->is_optional) {
            push @optional, $property_meta;
        }
        else {
            push @required, $property_meta;
        }
    }
    
    @result = ( 
        (sort { $a->{shell_args_position} <=> $b->{shell_args_position} } @positional),
        (sort { $a->property_name cmp $b->property_name } @required),
        (sort { $a->property_name cmp $b->property_name } @optional)
    );
    
    return @result;
}

sub _shell_arg_name_from_property_meta
{
    my ($self, $property_meta,$singularize) = @_;
    my $property_name = ($singularize ? $property_meta->singular_name : $property_meta->property_name);
    my $param_name = $property_name;
    $param_name =~ s/_/-/g;
    return $param_name; 
}

sub _shell_arg_getopt_qualifier_from_property_meta
{
    my ($self, $property_meta) = @_;

    my $many = ($property_meta->is_many ? '@' : ''); 
    if (defined($property_meta->data_type) and $property_meta->data_type =~ /Boolean/) {
        return '!' . $many;
    }
    else {
        return '=s' . $many;
    }
}

sub _shell_arg_usage_string_from_property_meta 
{
    my ($self, $property_meta) = @_;
    my $string = $self->_shell_arg_name_from_property_meta($property_meta);
    if ($property_meta->{shell_args_position}) {
        $string = uc($string);
    }

    if ($property_meta->{shell_args_position}) {
        if ($property_meta->is_optional) {
            $string = "[$string]";
        }
    }
    else {
        $string = "--$string";
        if (defined($property_meta->data_type) and $property_meta->data_type =~ /Boolean/) {
            $string = "[$string]";
        }
        else {
            if ($property_meta->is_many) {
                $string .= "=?[,?]";
            }
            else {
                $string .= '=?'; 
            }
            if ($property_meta->is_optional) {
                $string = "[$string]";
            }
        }
    }
    return $string;
}

sub _shell_arg_getopt_specification_from_property_meta 
{
    my ($self,$property_meta) = @_;
    my $arg_name = $self->_shell_arg_name_from_property_meta($property_meta);
    return (
        $arg_name .  $self->_shell_arg_getopt_qualifier_from_property_meta($property_meta),
        ($property_meta->is_many ? ($arg_name => []) : ())
    );
}


sub _shell_arg_getopt_complete_specification_from_property_meta 
{
    my ($self,$property_meta) = @_;
    my $arg_name = $self->_shell_arg_name_from_property_meta($property_meta);
    my $completions = $property_meta->valid_values;
    unless ($completions) {
        my $type = $property_meta->data_type;
        if ($type =~ /File(system|)(Path|)/i) {
            $completions = 'files';
        }
        elsif ($type =~ /Directory(Path|)/i) {
            $completions = 'directories'
        }
    }
    return (
        $arg_name .  $self->_shell_arg_getopt_qualifier_from_property_meta($property_meta),
        $completions, 
        ($property_meta->is_many ? ($arg_name => []) : ())
    );
}

sub _shell_args_getopt_specification 
{
    my $self = shift;
    my @getopt;
    my @params;
    for my $meta ($self->_shell_args_property_meta) {
        my ($spec, @params_addition) = $self->_shell_arg_getopt_specification_from_property_meta($meta);
        push @getopt,$spec;
        push @params, @params_addition; 
    }
    @getopt = sort @getopt;
    return { @params}, @getopt; 
}

sub _shell_args_getopt_complete_specification
{
    my $self = shift;
    my @getopt;
    my @params;
    for my $meta ($self->_shell_args_property_meta) {
        my ($spec, $completions, @params_addition) = $self->_shell_arg_getopt_specification_from_property_meta($meta);
        push @getopt,$spec, $completions;
        push @params, @params_addition; 
    }
    return { @params}, @getopt; 
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
    if ($self->is_sub_command_delegator) {
        return "...";
    }
    else {
        my $detailed = $self->_shell_args_usage_string;
        if (length($detailed) <= 20) {
            return $detailed;
        }
        else {
            return substr($detailed,0,17) . '...';
        }
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
    my $class = shift;
    my @paths = $class->sub_command_dirs;
    return unless @paths;
    @paths = 
        grep { s/\.pm$// } 
        map { glob("$_/*") } 
        grep { -d $_ }
        grep { defined($_) and length($_) } 
        @paths;
    return unless @paths;
    my @classes =
        grep {
            ($_->is_sub_command_delegator or !$_->is_abstract) 
        }
        grep { $_ and $_->isa('Command') }
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

    return if $sub_command =~ /^\-/;

    my $sub_class = join("", map { ucfirst($_) } split(/-/, $sub_command));
    $sub_class = $class . "::" . $sub_class;

    my $meta = UR::Object::Type->get($sub_class); # allow in memory classes
    unless ( $meta ) {
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
                $msgdata->{'dump_' . $type . '_messages'} = $type eq "status" ? 0 : 1;
            }

            if (my $code = $msgdata->{ $type . "_messages_callback"}) {
                $code->($self,$msg);
            }
            if (my $fh = $msgdata->{ "dump_" . $type . "_messages" }) {
                (ref($fh) ? $fh : $stderr)->print((($type eq "status" or $type eq 'usage') ? () : (uc($type), ": ")), (defined($msg) ? $msg : ""), "\n");
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

# Run the given command-line with stdout and stderr redirected to /dev/null
sub system_inhibit_std_out_err {
    my($self,$cmdline) = @_;

    open my $oldout, ">&STDOUT"     or die "Can't dup STDOUT: $!";
    open my $olderr, ">&", \*STDERR or die "Can't dup STDERR: $!";

    open(STDOUT,'>/dev/null');
    open(STDERR,'>/dev/null');

    my $ec = system ( $cmdline );

    open STDOUT, ">&", $oldout or die "Can't dup \$oldout: $!";
    open STDERR, ">&", $olderr or die "Can't dup \$olderr: $!";

    return $ec;
}


1;

__END__

=pod

=head1 NAME

Command - Base class for modules implementing the Command Pattern

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



