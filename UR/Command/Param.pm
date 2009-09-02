
package UR::Command::Param;

use strict;
use warnings;
use Getopt::Long;
#require UR;

# All legacy command line options generate objects of this type now.
# Specifying an option via the environment or command-line adjusts the "value" of the object.
# The legacy App->init() makes a subclass of UR::Context::Process with properties for each of 
# these with all of the involved properties.

our @original_argv;
our $argv_has_been_processed_successfully;
BEGIN {
    @original_argv = @ARGV;
    $argv_has_been_processed_successfully = "";
};

# This package level array is filled by other UR modules which add
# cmdline parameters, but have a bootstrapping/compile-order problem with this module.
# It allows the construction of the parameter objects to be deferred
# until the class is actually defined.


UR::Object::Type->define(
    class_name => 'UR::Command::Param',
    is => ['UR::Object'],
    english_name => 'ur command param',
    id_properties => [qw/command_id name/],
    properties => [
        command_id                       => { type => '', len => undef },
        name                             => { type => '', len => undef },
        _env_argv_value_override         => { type => '', len => undef },
        _specified_value                 => { type => '', len => undef },
        _action_on_set                   => { type => '', len => undef },
        category                         => { type => '', len => undef },
        default_value                    => { type => '', len => undef },
        doc                              => { type => '', len => undef },
        env_arg                          => { type => '', len => undef },
        getopt_arg                       => { type => '', len => undef },
        getopt_example                   => { type => '', len => undef },
    ],
    doc => 'A command parameter.',
);

sub action_on_set {
    my $self = shift;
    $self->_action_on_set(@_);
}

sub value {
    my $self = shift;
    if (@_) {
        my $value = shift;
        no warnings;
        unless ($self->_specified_value eq $value) {
            $self->_specified_value($value);
            $self->_on_value_set($value);
        }
    }
    else {
        unless ($argv_has_been_processed_successfully) {
            $self->class->process_argv_with_current_known_params;
            unless ($argv_has_been_processed_successfully) {
                Carp::confess("Bad command line options: @ARGV");
            }
        }
    }
    my $env_argv_value_override = $self->_env_argv_value_override;
    return $env_argv_value_override if defined $env_argv_value_override;
    my $specified_value = $self->_specified_value;
    return $specified_value if defined $specified_value;
    return $self->default_value;
}

sub _on_value_set {
    my $self = shift;
    my $value = shift;
    my $name = $self->name;
    my $action = $self->action_on_set;    
    if (my $env_arg = $self->env_arg) {
        $ENV{$env_arg} = $value;
    }    
    if (my $ref = ref($action)) {
        if ($ref eq "SCALAR") {
            $$action = $value;
        }
        elsif ($ref eq "CODE") {
            $action->($self->name,$value);
        }
        else {
            Carp::confess("$ref not supported FIXME!");
        }
    }
    else {
        Carp::confess("? action on $self->{name} $action");
    }
}

#
# THIS SHOULD BE THE ONLY CODE TO RUN DIRECTLY FROM A UR MODULE EXCEPT CLASS DEFS
#

# This is hard-linked by the old App::Getopt which uses it in alternate ways.
our $getopt_mod = 'Standard';

# all calls to add() put hashrefs in this array for backward compat
our @command_line_options;

=cut
# this call adds two basic options
__PACKAGE__->add(
    {
        name => 'help',
        option => '--help',
        message => 'print this message and exit',
        action => sub { UR::Context::Process->usage() && exit(0); exit(1); },
        module => $getopt_mod
    },
    {
        name => 'version',
        option => '--version',
        message => 'print version number and exit',
        action => sub { UR::Context::Process->print_version() && exit(0); exit(1); },
        module => $getopt_mod
    }
);
=cut

our @create_on_compile;
while (my $params = shift @create_on_compile) {    
    __PACKAGE__->define(@$params) 
        or Carp::confess(
            "Failed to define param: @$params: " 
            . __PACKAGE__->error_message
        );
}


sub create {
    shift->define(@_);
}

sub define {
    my $class = shift;
    my ($rule, %extra) = $class->get_rule_for_params(@_);    

    # see above for details on why action_on_set has issues
    my $action_on_set = delete $extra{action_on_set};
    if (%extra) {
        Carp::confess("Unknown params for creating $class!: " .
            YAML::Dump(\%extra)
        );
    }   
    
    my $self = $class->SUPER::define($rule->get_normalized_rule_equivalent);
    unless ($self) {
        print STDERR "failed to create on @_\n";
        return;
    }
    
    $self->action_on_set($action_on_set);    

    # handle parameters which use the environment for storage
    # print $self->name . ' has env ' . $self->env_arg . "\n";
    if (my $env_arg = $self->env_arg) {
        #print "checking env $env_arg $ENV{$env_arg}\n";
        if (exists $ENV{$env_arg}) {
            #print "using env $env_arg $ENV{$env_arg}\n";
            $self->_env_argv_value_override($ENV{$env_arg});
            $self->_on_value_set($ENV{$env_arg});
        }
    }   
 
    # Handle parameters for "main", which is a dummy command representing
    # the current process, with values mined from @ARGV.
    if ($self->command_id eq "main") {
        # The parameter is for "main", the program itself.
        # Attempt to process @ARGV incrementally.
        # This only actually changes @ARGV when all of options can be parsed.
        
        # Ensure the module does not have more parameters to create during
        # compilation.  This should run after the last parameter is processed.
        unless (@create_on_compile) {
            # The module is NOT still compiling.            
            $class->process_argv_with_current_known_params;            
        }        
    }

    return $self;
}

sub add {
    my $class = shift;
    
    my (%opts) = @_;

    # loop though arguments
    while (my ($opt, $val) = each(%opts))
    {
        my $opt_hash;
        if (ref($val) eq 'HASH')
        {
            $opt_hash = $val;
            $opt_hash->{option} ||= "--$opt";
            $opt_hash->{name} ||= "$opt";
            if ($opt_hash->{msg} && !exists($opt_hash->{message}))
            {
                $opt_hash->{message} = $opt_hash->{msg};
            }
        }
        else
        {
            # split up option specification
            if (my ($name, $arg) = $opt =~ m/^([-|\w]+)([=:][fis]@?|!)?$/)
            {
                # create hash
                $opt_hash =
                {
                    name => $name,
                    option => "--$opt",
                    message => '(undocumented)',
                    action => $val,
                };
                $opt_hash->{argument} = $arg if $arg;
            }
            else
            {
                # should this just return undef?
                die("unable to parse option '$opt'");
            }
        }
        # set originating module
        $opt_hash->{module} ||= ((caller(0))[0]);
        $opt_hash->{module} = UR::Context::Process->pkg_name
            if $opt_hash->{module} eq 'main';

        # check for invalid characters in option
        if ($opt_hash->{option} =~ m/_/)
        {
            $class->warning_message("underscores are not allowed in options, "
                                    . "use hyphens: " . $opt_hash->{option});
        }
        
        # This must work during the compile phase, in which this UR::Command::Param
        # module might not be completely available.
        my @param_constructor_params = ( 
                command_id          => "main",
                name                => $opt_hash->{name},
                category            => $opt_hash->{module},
                doc                 => $opt_hash->{message},
                getopt_arg          => $opt_hash->{argument},
                getopt_example      => $opt_hash->{option},
                action_on_set       => $opt_hash->{action},
                env_arg             => $opt_hash->{env_arg},
                default_value       => $opt_hash->{default_value},
        );
        if (UNIVERSAL::can("UR::Command::Param","get")) {
            my $obj = UR::Command::Param->create(@param_constructor_params);
            unless ($obj) {
                Carp::confess("Failed to create UR::Command::Param object for App::Getop option.");
            }
            #print "built $opt_hash->{name} param\n";
        }
        else {
            push @UR::Command::Param::create_on_compile, \@param_constructor_params;
            #print "push $opt_hash->{name} onto list\n";
        }
            
        push(@command_line_options, $opt_hash);
    }

    return 1;
}

# TODO: move me to the command object
my $prevent_recursion = 0;

sub process_argv_with_current_known_params {
    return if $prevent_recursion;

    my $class = shift;
    if (not @ARGV) {
        $argv_has_been_processed_successfully = 1;
    }
    return 1 if $argv_has_been_processed_successfully;

    my @params_thus_far = UR::Command::Param->get(command_id => "main");
    return unless @params_thus_far;
    
    my @test_args_for_getopt = 
        map { $_->_as_getopt_test_params } 
        @params_thus_far;
    
    my @prev_argv = @ARGV;
    @ARGV = @original_argv;    
    #print "\ttrying @test_args_for_getopt on @ARGV\n";
    my %values;
    my $args_are_complete;
    do {
        local %SIG;
        $SIG{__WARN__} = \&UR::Util::null_sub;
        $args_are_complete = GetOptions(\%values,@test_args_for_getopt);
    };

    #use Data::Dumper;
    #print Dumper("args\n",\%values);

    if ($args_are_complete) {    
        #print "\tWORKED: @ARGV\n";
        $argv_has_been_processed_successfully = 1;
        # keep @ARGV in its post-processed state
        # it will have non-option arguments        
    }
    else {
        #print "\tFAILED: @ARGV\n";
        @ARGV = @prev_argv;
        #return;
    }

    for my $name (keys %values) {
        my $param = UR::Command::Param->get(
            command_id => "main",
            name => $name
        );
        die "No command? $name\n" unless $param;
        my $value = $values{$name};
        $param->_env_argv_value_override($value);
        $prevent_recursion = 1;
        $param->_on_value_set($value);
        $prevent_recursion = 0;
    }

    return ($argv_has_been_processed_successfully ? 1 : ());
}

sub argv_has_been_processed_successfully {
    shift->process_argv_with_current_known_params();
    return $argv_has_been_processed_successfully;
}

sub as_getopt_params {
    my $self = shift;
    my ($name, $arg, $action) = ($self->name, $self->getopt_arg, $self->action_on_set);
    return ( ($arg ? ("$name$arg") : $name), $action );
}    

sub _as_getopt_test_params {
    my $self = shift;    
    my ($name_plus_arg, $action) = $self->as_getopt_params(); 
    return $name_plus_arg;
}

1;
#$Header$
