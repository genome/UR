package Command::V2;  # additional methods to dispatch from a command-line
use strict;
use warnings;

sub execute_with_shell_params_and_exit {
    # This automatically parses command-line options and "does the right thing":
    # TODO: abstract out all dispatchers for commands into a given API
    my $class = shift;
    
    if (@_) {
        die "No params expected for execute_with_shell_params_and_exit()!";
    }

    $Command::entry_point_class ||= $class;
    $Command::entry_point_bin ||= File::Basename::basename($0);

    if ($ENV{COMP_CWORD}) {
        require Getopt::Complete;
        my @spec = $class->resolve_option_completion_spec();
        my $options = Getopt::Complete::Options->new(@spec);
        $options->handle_shell_completion;
        die "error: failed to exit after handling shell completion!";
    }

    my @argv = @ARGV;
    @ARGV = ();
    my $exit_code;
    eval {
        $exit_code = $class->_execute_with_shell_params_and_return_exit_code(@argv);
        UR::Context->commit or die "Failed to commit!: " . UR::Context->error_message();
    };
    if ($@) {
        $class->error_message($@);
        UR::Context->rollback or die "Failed to rollback changes after failed commit!!!\n";
        $exit_code = 255 unless ($exit_code);
    }
    exit $exit_code;
}

sub _execute_with_shell_params_and_return_exit_code {
    my $class = shift;
    my @argv = @_;

    my $original_cmdline = join("\0",$0,@argv);

    # make --foo=bar equivalent to --foo bar
    @argv = map { ($_ =~ /^(--\w+?)\=(.*)/) ? ($1,$2) : ($_) } @argv;
    my ($delegate_class, $params, $errors) = $class->resolve_class_and_params_for_argv(@argv);

    my $exit_code;
    if ($errors and @$errors) {
        $delegate_class->dump_status_messages(1);
        $delegate_class->dump_warning_messages(1);
        $delegate_class->dump_error_messages(1);
        for my $error (@$errors) {
            $delegate_class->error_message(join(' ', $error->property_names) . ": " . $error->desc);
        }        
        $exit_code = 1;
    }
    else {
        my $rv = $class->_execute_delegate_class_with_params($delegate_class,$params,$original_cmdline);
        $exit_code = $delegate_class->exit_code_for_return_value($rv);
    }

    return $exit_code;
}


sub _execute_delegate_class_with_params {
    # this is called by both the shell dispatcher and http dispatcher for now
    my ($class, $delegate_class, $params, $original_cmdline) = @_;

    unless ($delegate_class) {
        $class->dump_status_messages(1);
        $class->dump_warning_messages(1);
        $class->dump_error_messages(1);
        $class->dump_usage_messages(1);
        $class->dump_debug_messages(0);
        $class->usage_message($class->help_usage_complete_text);
        return;
    }

    $delegate_class->dump_status_messages(1);
    $delegate_class->dump_warning_messages(1);
    $delegate_class->dump_error_messages(1);
    $delegate_class->dump_usage_messages(1);
    $delegate_class->dump_debug_messages(0);

    # FIXME There should be a better check for params that are there because they came from the
    # command line, and params that exist for infrastructural purposes.  'original_command_line'
    # won't ever be given on the command line and shouldn't count toward the next test.
    # maybe check the is_input properties...
    if ( !defined($params) ) {
        my $command_name = $delegate_class->command_name;
        $delegate_class->status_message($delegate_class->help_usage_complete_text);
        $delegate_class->error_message("Please specify valid params for '$command_name'.");
        return;
    }

    if ( $params->{help} ) {
        $delegate_class->usage_message($delegate_class->help_usage_complete_text);
        return 1;
    }

    $params->{'original_command_line'} = $original_cmdline if (defined $original_cmdline);
    my $command_object = $delegate_class->create(%$params);

    unless ($command_object) {
        # The delegate class should have emitted an error message.
        # This is just in case the developer is sloppy, and the user will think the task did not fail.
        print STDERR "Exiting.\n";
        return;
    }

    $command_object->dump_status_messages(1);
    $command_object->dump_warning_messages(1);
    $command_object->dump_error_messages(1);
    $command_object->dump_debug_messages(0);

    my $rv = $command_object->execute($params);

    unless ($rv) {
        my $command_name = $command_object->command_name;
        $command_object->error_message("Please see '$command_name --help' for more information.");
    }

    if ($command_object->__errors__) {
        $command_object->delete;
    }

    return $rv;
}

sub resolve_class_and_params_for_argv {
    # This is used by execute_with_shell_params_and_exit, but might be used within an application.
    my $self = shift;
    my @argv = @_;
    
    my ($params_hash,@spec) = $self->_shell_args_getopt_specification;
    unless (grep { /^help\W/ } @spec) {
        push @spec, "help!";
    }

    my @error_tags;

    # Thes nasty GetOptions modules insist on working on
    # the real @ARGV, while we like a little more flexibility.
    # Not a problem in Perl. :)  (which is probably why it was never fixed)
    local @ARGV;
    @ARGV = @argv;
   
    do {
        # GetOptions also likes to emit warnings instead of return a list of errors :( 
        my @errors;
        local $SIG{__WARN__} = sub { push @errors, @_ };
        
        ## Change the pattern to be '--', '-' followed by a non-digit, or '+'.
        ## This s the effect of treating a negative number as a value of an option.
        ## This means that we won't be allowed to have an option named, say, -1.
        ## But since command modules' properties have to be allowable function names,
        ## and "1" is not a valid function name, it's not really a problem
        #Getopt::Long::Configure('prefix_pattern=--|-(?!\D)|\+');
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
        for (my $n=0; $n < @ARGV; $n++) {
            my $name = $names[$n];
            unless ($name) {
                $self->error_message("Unexpected bare arguments: @ARGV[$n..$#ARGV]!");
                return($self, undef);
            }
            my $value = $ARGV[$n];
            my $meta = $self->__meta__->property_meta_for_name($name);
            if ($meta->is_many and $n == $#names) {
                # slurp the rest
                $params_hash->{$name} = [@ARGV[$n..$#ARGV]];
                last;
            }
            else {
                $params_hash->{$name} = $value;
            }
        }
    } 
    
    if (@ARGV and not $self->_bare_shell_argument_names) {
        ## argv but no names
        $self->error_message("Unexpected bare arguments: @ARGV!");
        return($self, undef);
    }

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

        } elsif ($value eq q('') or $value eq q("")) {
            # Handle the special values '' and "" to mean undef/NULL
            $params_hash->{$key} = '';
        }

        # turn dashes into underscores
        my $new_key = $key;

        next unless ($new_key =~ tr/-/_/);
        if (exists $params_hash->{$new_key} && exists $params_hash->{$key}) {
            # this corrects a problem where is_many properties badly interact
            # with bare args leaving two entries in the hash like:
            # a-bare-opt => [], a_bare_opt => ['with','vals']
            delete $params_hash->{$key};
            next;
        }
        $params_hash->{$new_key} = delete $params_hash->{$key};
    }

    # futher work is looking for errors, and may display them
    # if help is set, return now
    # we might have returned sooner, but having full info available
    # allows for dynamic help
    if ($params_hash->{help}) {
        return ($self, $params_hash);
    }

    ##
    my $params = $params_hash;
    my $class = $self->class;
    
    if (my @errors = $self->_errors_from_missing_parameters($params)) {
        return ($class, $params, \@errors);
    }

    unless (@_) {
        return ($class, $params);
    }

    # should this be moved up into the methods which are only called
    # directly from the shell, or is it okay everywhere in this module to
    # presume we're a direct cmdline call? -ssmith
    local $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;

    my @params_to_resolve = $self->_params_to_resolve($params);
    for my $p (@params_to_resolve) {
        my $param_arg_str = join(',', @{$p->{value}});
        my $pmeta = $self->__meta__->property($p->{name}); 

        my @params;
        eval {
            @params = $self->resolve_param_value_from_cmdline_text($p);
        };

        if ($@) {
            push @error_tags, UR::Object::Tag->create(
                type => 'invalid',
                properties => [$p->{name}],
                desc => "Errors while resolving from $param_arg_str: $@",
            );
        }
        if (@params and $params[0]) {
            if ($pmeta->{'is_many'}) {
                $params->{$p->{name}} = \@params;
            }
            else {
                $params->{$p->{name}} = $params[0];
            }
        }
        else {
            push @error_tags, UR::Object::Tag->create(
                type => 'invalid',
                properties => [$p->{name}],
                desc => "Problem resolving from $param_arg_str.",
            );
        }
    }

    if (@error_tags) {
        return ($class, undef, \@error_tags);
    }
    else {
        return ($class, $params);
    }
}

sub resolve_option_completion_spec {
    my $class = shift;
    my @completion_spec = $class->_shell_args_getopt_complete_specification;
    no warnings;
    unless (grep { /^help\W/ } @completion_spec) {
        push @completion_spec, "help!" => undef;
    }
    return \@completion_spec
}

sub _errors_from_missing_parameters {
    my ($self, $params) = @_;

    my $class_meta = $self->__meta__;

    my @property_names;
    if (my $has = $class_meta->{has}) {
        @property_names = $self->_unique_elements(keys %$has);
    }
    my @property_metas = map { $class_meta->property_meta_for_name($_); } @property_names;

    my @error_tags;
    for my $property_meta (@property_metas) {
        my $pn = $property_meta->property_name;

        next if $property_meta->is_optional;
        next if $property_meta->implied_by;
        next if defined $property_meta->default_value;
        next if defined $params->{$pn};

        my $arg = $pn;
        $arg =~ s/_/-/g;
        $arg = "--$arg";

        if ($property_meta->is_output and not $property_meta->is_input and not $property_meta->is_param) {
            if ($property_meta->_data_type_as_class_name->__meta__->data_source) {
                # outputs with a data source do not need a specification 
                # on the cmdline to "store" them after execution
                next;
            }
            else {
                push @error_tags, UR::Object::Tag->create(
                    type => 'invalid',
                    properties => [$pn],
                    desc => "Output requires specified destination: " . $arg . "."
                );
            }
        }
        else {
            $DB::single = 1;
            push @error_tags, UR::Object::Tag->create(
                type => 'invalid',
                properties => [$pn],
                desc => "Missing required parameter: " . $arg . "."
            );
        }
    }

    return @error_tags;
}

sub _params_to_resolve {
    my ($self, $params) = @_;
    my @params_to_resolve;
    if ($params) {
        my $cmeta = $self->__meta__;
        my @params_will_require_verification;
        my @params_may_require_verification;

        for my $param_name (keys %$params) {
            my $pmeta = $cmeta->property($param_name); 
            unless ($pmeta) {
                # This message was a die after a next, so I guess it isn't supposed to be fatal?
                $self->warning_message("No metadata for property '$param_name'");
                next;
            }

            my $param_type = $pmeta->data_type;
            next unless($self->_can_resolve_type($param_type));

            my $param_arg = $params->{$param_name};
            if (my $arg_type = ref($param_arg)) {
                next if $arg_type eq $param_type; # param is already the right type
                if ($arg_type ne 'ARRAY') {
                    $self->error_message("no handler for property '$param_name' with argument type " . ref($param_arg));
                    next;
                }
            } else {
                $param_arg = [$param_arg];
            }
            next unless (@$param_arg);

            my $resolve_info = {
                name => $param_name,
                class => $param_type,
                value => $param_arg,
            };
            push(@params_to_resolve, $resolve_info);

            my $require_user_verify = $pmeta->{'require_user_verify'};
            if ( defined($require_user_verify) ) {
                push @params_will_require_verification, "'$param_name'" if ($require_user_verify);
            } else {
                push @params_may_require_verification, "'$param_name'";
            }
        }

        my @adverbs = ('will', 'may');
        my @params_adverb_require_verification = (
            \@params_will_require_verification,
            \@params_may_require_verification,
        );
        for (my $i = 0; $i < @adverbs; $i++) {
            my $adverb = $adverbs[$i];
            my @param_adverb_require_verification = @{$params_adverb_require_verification[$i]};
            next unless (@param_adverb_require_verification);

            if (@param_adverb_require_verification > 1) {
                $param_adverb_require_verification[-1] = 'and ' . $param_adverb_require_verification[-1];
            }
            my $param_str = join(', ', @param_adverb_require_verification);
            $self->status_message($param_str . " $adverb require verification...");
        }
    }
    return @params_to_resolve;
}

sub _can_resolve_type {
    my ($self, $type) = @_;

    return 0 unless($type);

    my $non_classes = 0;
    if (ref($type) ne 'ARRAY') {
        $non_classes = $type !~ m/::/;
    } else {
        $non_classes = scalar grep { ! m/::/ } @$type;
    }
    return $non_classes == 0;
}

sub _shell_args_property_meta {
    my $self = shift;
    my $class_meta = $self->__meta__;

    # Find which property metas match the rules.  We have to do it this way
    # because just calling 'get_all_property_metas()' will product multiple matches 
    # if a property is overridden in a child class
    my $rule = UR::Object::Property->define_boolexpr(@_);
    my %seen;
    my (@positional,@required,@optional);

    my @properties_with_position = map { [ $_->position_in_module_header, $_ ] }
                                   $class_meta->properties();
    my @sorted =
        sort { 
            $a->[0] <=> $b->[0]
        } 
        @properties_with_position;
    my @property_meta = map { $_->[1] } @sorted;
    foreach my $property_meta (@property_meta) {
        my $property_name = $property_meta->property_name;

        next if $seen{$property_name}++;
        next unless $rule->evaluate($property_meta);

        next unless $property_meta->can("is_param") and ($property_meta->is_param or $property_meta->is_input);

        next if $property_name eq 'id';
        next if $property_name eq 'result';
        next if $property_name eq 'is_executed';
        next if $property_name eq 'original_command_line';
        next if $property_name =~ /^_/;

        next if $property_meta->implied_by;
        next if $property_meta->is_calculated;
        # Kept commented out from UR's Command.pm, I believe is_output is a workflow property
        # and not something we need to exclude (counter to the old comment below).
        #next if $property_meta->{is_output}; # TODO: This was breaking the G::M::T::Annotate::TranscriptVariants annotator. This should probably still be here but temporarily roll back
        next if $property_meta->is_transient;
        next if $property_meta->is_constant;
        if (($property_meta->is_delegated) || (defined($property_meta->data_type) and $property_meta->data_type =~ /::/)) {
            next unless($self->can('resolve_param_value_from_cmdline_text'));
        }
        else {
            next unless($property_meta->is_mutable);
        }
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

    @required   = map { [ $_->position_in_module_header, $_ ] } @required;
    @optional   = map { [ $_->position_in_module_header, $_ ] } @optional;
    @positional = map { [ $_->{shell_args_position}, $_ ] } @positional;

    my @result;
    @result = ( 
        (sort { $a->[0] cmp $b->[0] } @required),
        (sort { $a->[0] cmp $b->[0] } @optional),
        (sort { $a->[0] <=> $b->[0] } @positional),
    );

    return map { $_->[1] } @result;
}


sub _shell_arg_name_from_property_meta {
    my ($self, $property_meta,$singularize) = @_;
    my $property_name = ($singularize ? $property_meta->singular_name : $property_meta->property_name);
    my $param_name = $property_name;
    $param_name =~ s/_/-/g;
    return $param_name; 
}

sub _shell_arg_getopt_qualifier_from_property_meta {
    my ($self, $property_meta) = @_;

    my $many = ($property_meta->is_many ? '@' : ''); 
    if (defined($property_meta->data_type) and $property_meta->data_type =~ /Boolean/) {
        return '!' . $many;
    }
    #elsif ($property_meta->is_optional) {
    #    return ':s' . $many;
    #}
    else {
        return '=s' . $many;
    }
}

sub _shell_arg_usage_string_from_property_meta {
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

sub _shell_arg_getopt_specification_from_property_meta {
    my ($self,$property_meta) = @_;
    my $arg_name = $self->_shell_arg_name_from_property_meta($property_meta);
    return (
        $arg_name .  $self->_shell_arg_getopt_qualifier_from_property_meta($property_meta),
        ($property_meta->is_many ? ($arg_name => []) : ())
    );
}


sub _shell_arg_getopt_complete_specification_from_property_meta {
    my ($self,$property_meta) = @_;
    my $arg_name = $self->_shell_arg_name_from_property_meta($property_meta);
    my $completions = $property_meta->valid_values;
    if ($completions) {
        if (ref($completions) eq 'ARRAY') {
            $completions = [ @$completions ];
        }
    }
    else {
        my $type = $property_meta->data_type;
        my @complete_as_files = (
            'File','FilePath','Filesystem','FileSystem','FilesystemPath','FileSystemPath',
            'Text','String',
        );
        my @complete_as_directories = (
            'Directory','DirectoryPath','Dir','DirPath',
        );
        if (!defined($type)) {
            $completions = 'files'; 
        }
        else {
            for my $pattern (@complete_as_files) {
                if (!$type || $type eq $pattern) {
                    $completions = 'files';
                    last;
                }
            }
            for my $pattern (@complete_as_directories) {
                if ( $type && $type eq $pattern) {
                    $completions = 'directories';
                    last;
                }
            }
        }
    }
    return (
        $arg_name .  $self->_shell_arg_getopt_qualifier_from_property_meta($property_meta),
        $completions, 
#        ($property_meta->is_many ? ($arg_name => []) : ())
    );
}

sub _shell_args_getopt_specification {
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

sub _shell_args_getopt_complete_specification {
    my $self = shift;
    my @getopt;
    for my $meta ($self->_shell_args_property_meta) {
        my ($spec, $completions) = $self->_shell_arg_getopt_complete_specification_from_property_meta($meta);
        push @getopt, $spec, $completions;
    }
    return @getopt; 
}


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

#
# Logic to turn command-line text into objects for parameter/input values
#

our %ALTERNATE_FROM_CLASS = ();

# This will prevent infinite loops during recursion.
our %SEEN_FROM_CLASS = ();
our $MESSAGE;

sub resolve_param_value_from_cmdline_text {
    my ($self, $param_info) = @_;
    my $param_name  = $param_info->{name};
    my $param_class = $param_info->{class};
    my @param_args  = @{$param_info->{value}};
    my $param_str   = join(',', @param_args);

    my @param_class;
    if (ref($param_class) eq 'ARRAY') {
        @param_class = @$param_class;
    } else {
        @param_class = ($param_class);
    }
    undef($param_class);
    #this splits a bool_expr if multiples of the same field are listed, e.g. name=foo,name=bar
    if (@param_args > 1) {
        my %bool_expr_type_count;
        my @bool_expr_type = map {split(/[=~]/, $_)} @param_args;
        for my $type (@bool_expr_type) {
            $bool_expr_type_count{$type}++;
        }
        my $duplicate_bool_expr_type = 0;
        for my $type (keys %bool_expr_type_count) {
            $duplicate_bool_expr_type++ if ($bool_expr_type_count{$type} > 1);
        }
        unshift @param_args, $param_str unless($duplicate_bool_expr_type);
    }

    my $pmeta = $self->__meta__->property($param_name);

    my $param_resolve_message = "Resolving parameter '$param_name' from command argument '$param_str'...";
    my @results;
    my $require_user_verify = $pmeta->{'require_user_verify'};
    for (my $i = 0; $i < @param_args; $i++) {
        my $arg = $param_args[$i];
        my @arg_results;
        (my $arg_display = $arg) =~ s/,/ AND /g; 

        for my $param_class (@param_class) {
            %SEEN_FROM_CLASS = ();
            # call resolve_param_value_from_text without a via_method to "bootstrap" recursion
            @arg_results = eval{$self->resolve_param_value_from_text($arg, $param_class)};
        } 
        last if ($@ && !@arg_results);

        $require_user_verify = 1 if (@arg_results > 1 && !defined($require_user_verify));
        if (@arg_results) {
            push @results, @arg_results;
            last if ($arg =~ /,/); # the first arg is all param_args as BoolExpr, if it returned values finish; basically enforicing AND (vs. OR)
        }
        elsif (@param_args > 1 ) {
            #print STDERR "WARNING: No match found for $arg!\n";
        }
    }
    if (@results) {
        $self->status_message($param_resolve_message . " found " . @results);
    }
    else {
        $self->status_message($param_resolve_message . " none found.");
    }

    return unless (@results);

    my $limit_results_method = "_limit_results_for_$param_name";
    if ( $self->can($limit_results_method) ) {
        @results = $self->$limit_results_method(@results);
        return unless (@results);
    }
    @results = $self->_unique_elements(@results);
    if ($require_user_verify) {
        if (!$pmeta->{'is_many'} && @results > 1) {
            $MESSAGE .= "\n" if ($MESSAGE);
            $MESSAGE .= "'$param_name' expects only one result.";
        }
        @results = $self->_get_user_verification_for_param_value($param_name, @results);
    }
    while (!$pmeta->{'is_many'} && @results > 1) {
        $MESSAGE .= "\n" if ($MESSAGE);
        $MESSAGE .= "'$param_name' expects only one result, not many!";
        @results = $self->_get_user_verification_for_param_value($param_name, @results);
    }

    if (wantarray) {
        return @results;
    }
    elsif (not defined wantarray) {
        return;
    }
    elsif (@results > 1) {
        Carp::confess("Multiple matches found!");
    }
    else {
        return $results[0];
    }
}

sub resolve_param_value_from_text {
    my ($self, $param_arg, $param_class, $via_method) = @_;

    unless ($param_class) {
        $param_class = $self->class;
    }

    $SEEN_FROM_CLASS{$param_class} = 1;
    my @results;
    # try getting BoolExpr, otherwise fallback on '_resolve_param_value_from_text_by_name_or_id' parser
    eval { @results = $self->_resolve_param_value_from_text_by_bool_expr($param_class, $param_arg); };
    if (!@results && !$@) {
        # no result and was valid BoolExpr then we don't want to break it apart because we
        # could query enormous amounts of info
        die $@;
    }
    # the first param_arg is all param_args to try BoolExpr so skip if it has commas
    if (!@results && $param_arg !~ /,/) {
        my @results_by_string;
        if ($param_class->can('_resolve_param_value_from_text_by_name_or_id')) {
            @results_by_string = $param_class->_resolve_param_value_from_text_by_name_or_id($param_arg);
        }
        else {
            @results_by_string = $self->_resolve_param_value_from_text_by_name_or_id($param_class, $param_arg); 
        }
        push @results, @results_by_string;
    }
    # if we still don't have any values then try via alternate class
    if (!@results && $param_arg !~ /,/) {
        @results = $self->_resolve_param_value_via_related_class_method($param_class, $param_arg, $via_method);
    }

    if ($via_method) {
        @results = map { $_->$via_method } @results;
    }

    if (wantarray) {
        return @results;
    }
    elsif (not defined wantarray) {
        return;
    }
    elsif (@results > 1) {
        Carp::confess("Multiple matches found!");
    }
    else {
        return $results[0];
    }
}

sub _resolve_param_value_via_related_class_method {
    my ($self, $param_class, $param_arg, $via_method) = @_;
    my @results;
    my $via_class;
    if (exists($ALTERNATE_FROM_CLASS{$param_class})) {
        $via_class = $param_class;
    }
    else {
        for my $class (keys %ALTERNATE_FROM_CLASS) {
            if ($param_class->isa($class)) {
                if ($via_class) {
                    $self->error_message("Found additional via_class $class but already found $via_class!");
                }
                $via_class = $class;
            }
        }
    }
    if ($via_class) {
        my @from_classes = sort keys %{$ALTERNATE_FROM_CLASS{$via_class}};
        while (@from_classes && !@results) {
            my $from_class  = shift @from_classes;
            my @methods = @{$ALTERNATE_FROM_CLASS{$via_class}{$from_class}};
            my $method;
            if (@methods > 1 && !$via_method && !$ENV{UR_NO_REQUIRE_USER_VERIFY}) {
                $self->status_message("Trying to find $via_class via $from_class...\n");
                my $method_choices;
                for (my $i = 0; $i < @methods; $i++) {
                    $method_choices .= ($i + 1) . ": " . $methods[$i];
                    $method_choices .= " [default]" if ($i == 0);
                    $method_choices .= "\n";
                }
                $method_choices .= (scalar(@methods) + 1) . ": none\n";
                $method_choices .= "Which method would you like to use?";
                my $response = $self->_ask_user_question($method_choices, 0, '\d+', 1, '#');
                if ($response =~ /^\d+$/) {
                    $response--;
                    if ($response == @methods) {
                        $method = undef;
                    }
                    elsif ($response >= 0 && $response <= $#methods) {
                        $method = $methods[$response];
                    }
                    else {
                        $self->error_message("Response was out of bounds, exiting...");
                        exit;
                    }
                    $ALTERNATE_FROM_CLASS{$via_class}{$from_class} = [$method];
                }
                elsif (!$response) {
                    $self->status_message("Exiting...");
                }
            }
            else {
                $method = $methods[0];
            }
            unless($SEEN_FROM_CLASS{$from_class}) {
                #$self->debug_message("Trying to find $via_class via $from_class->$method...");
                @results = eval {$self->resolve_param_value_from_text($param_arg, $from_class, $method)};
            }
        } # END for my $from_class (@from_classes)
    } # END if ($via_class)
    return @results;
}

sub _resolve_param_value_from_text_by_bool_expr {
    my ($self, $param_class, $arg) = @_;

    my @results;
    my $bx = eval {
        UR::BoolExpr->resolve_for_string($param_class, $arg);
    };
    if ($bx) {
        @results = $param_class->get($bx);
    }
    else {
        die "Not a valid BoolExpr";
    }
    #$self->debug_message("B: $param_class '$arg' " . scalar(@results));

    return @results;
}

sub _resolve_param_value_from_text_by_name_or_id {
    my ($self, $param_class, $str) = @_;
    my (@results);

    my $class_meta = $param_class->__meta__;
    my @id_property_names = $class_meta->id_property_names;
    if (@id_property_names == 0) {
        die "Failed to determine id property names for class $param_class.";
    }

    my $first_type = $class_meta->property_meta_for_name($id_property_names[0])->data_type || '';
    if (@id_property_names > 1 or $first_type eq 'Text' or $str =~ /^-?\d+$/) { # try to get by ID
        @results = $param_class->get($str);
    }
    if (!@results && $param_class->can('name')) {
        @results = $param_class->get(name => $str);
        unless (@results) {
            @results = $param_class->get("name like" => "$str");
        }
    }
    #$self->debug_message("S: $param_class '$str' " . scalar(@results));

    return @results;
}

sub _get_user_verification_for_param_value {
    my ($self, $param_name, @list) = @_;

    my $n_list = scalar(@list);
    if ($n_list > 200 && !$ENV{UR_NO_REQUIRE_USER_VERIFY}) {
        my $response = $self->_ask_user_question("Would you [v]iew all $n_list item(s) for '$param_name', (p)roceed, or e(x)it?", 0, '[v]|p|x', 'v');
        if(!$response || $response eq 'x') {
            $self->status_message("Exiting...");
            exit;
        }
        return @list if($response eq 'p');
    }

    my @new_list;
    while (!@new_list) {
        @new_list = $self->_get_user_verification_for_param_value_drilldown($param_name, @list);
    }

    my @ids = map { $_->id } @new_list;
    $self->status_message("The IDs for your selection are:\n" . join(',', @ids) . "\n\n");
    return @new_list;
}

sub _get_user_verification_for_param_value_drilldown {
    my ($self, $param_name, @results) = @_;
    my $n_results = scalar(@results);
    my $pad = length($n_results);

    # Allow an environment variable to be set to disable the require_user_verify attribute
    return @results if ($ENV{UR_NO_REQUIRE_USER_VERIFY});
    return if (@results == 0);

    my @dnames = map {$_->__display_name__} grep { $_->can('__display_name__') } @results;
    my $max_dname_length = @dnames ? length((sort { length($b) <=> length($a) } @dnames)[0]) : 0;
    my @statuses = map {$_->status} grep { $_->can('status') } @results;
    my $max_status_length = @statuses ? length((sort { length($b) <=> length($a) } @statuses)[0]) : 0;

    my @results_with_display_name_and_class = map { [ $_->__display_name__, $_->class, $_ ] } @results;
    @results = map { $_->[2] }
               sort { $a->[1] cmp $b->[1] }
               sort { $a->[0] cmp $b->[0] }
               @results_with_display_name_and_class;

    my @classes = $self->_unique_elements(map {$_->class} @results);

    my $response;
    my @caller = caller(1);
    while (!$response) {
        $self->status_message("\n");
        # TODO: Replace this with lister?
        for (my $i = 1; $i <= $n_results; $i++) {
            my $param = $results[$i - 1];
            my $num = $self->_pad_string($i, $pad);
            my $msg = "$num:";
            $msg .= ' ' . $self->_pad_string($param->__display_name__, $max_dname_length, 'suffix');
            my $status = ' ';
            if ($param->can('status')) {
                $status = $param->status;
            }
            $msg .= "\t" . $self->_pad_string($status, $max_status_length, 'suffix');
            $msg .= "\t" . $param->class if (@classes > 1);
            $self->status_message($msg);
        }
        if ($MESSAGE) {
            $MESSAGE = "\n" . '*'x80 . "\n" . $MESSAGE . "\n" . '*'x80 . "\n";
            $self->status_message($MESSAGE);
            $MESSAGE = '';
        }
        my $pretty_values = '(c)ontinue, (h)elp, e(x)it';
        my $valid_values = '\*|c|h|x|[-+]?[\d\-\., ]+';
        if ($caller[3] =~ /_trim_list_from_response/) {
            $pretty_values .= ', (b)ack';
            $valid_values .= '|b';
        }
        $response = $self->_ask_user_question("Please confirm the above items for '$param_name' or modify your selection.", 0, $valid_values, 'h', $pretty_values.', or specify item numbers to use');
        if (lc($response) eq 'h' || !$self->_validate_user_response_for_param_value_verification($response)) {
            $MESSAGE .= "\n" if ($MESSAGE);
            $MESSAGE .=
            "Help:\n".
            "* Specify which elements to keep by listing them, e.g. '1,3,12' would keep\n".
            "  items 1, 3, and 12.\n".
            "* Begin list with a minus to remove elements, e.g. '-1,3,9' would remove\n".
            "  items 1, 3, and 9.\n".
            "* Ranges can be used, e.g. '-11-17, 5' would remove items 11 through 17 and\n".
            "  remove item 5.";
            $response = '';
        }
    }
    if (lc($response) eq 'x') {
        $self->status_message("Exiting...");
        exit;
    }
    elsif (lc($response) eq 'b') {
        return;
    }
    elsif (lc($response) eq 'c' | $response eq '*') {
        return @results;
    }
    elsif ($response =~ /^[-+]?[\d\-\., ]+$/) {
        @results = $self->_trim_list_from_response($response, $param_name, @results);
        return @results;
    }
    else {
        die $self->error_message("Conditional exception, should not have been reached!");
    }
}

sub _ask_user_question {
    my $self = shift;
    my $question = shift;
    my $timeout = shift;
    my $valid_values = shift || "yes|no";
    my $default_value = shift || undef;
    my $pretty_valid_values = shift || $valid_values;
    $valid_values = lc($valid_values);
    my $input;
    $timeout = 60 unless(defined($timeout));

    local $SIG{ALRM} = sub { print STDERR "Exiting, failed to reply to question '$question' within '$timeout' seconds.\n"; exit; };
    print STDERR "\n$question\n";
    print STDERR "Reply with $pretty_valid_values: ";

    unless ($self->_can_interact_with_user) {
        print STDERR "\n";
        die $self->error_message("Attempting to ask user question but cannot interact with user!");
    }

    alarm($timeout) if ($timeout);
    chomp($input = <STDIN>);
    alarm(0) if ($timeout);

    print STDERR "\n";

    if(lc($input) =~ /^$valid_values$/) {
        return lc($input);
    }
    elsif ($default_value) {
        return $default_value;
    }
    else {
        $self->error_message("'$input' is an invalid answer to question '$question'\n\n");
        return;
    }
}

sub _validate_user_response_for_param_value_verification {
    my ($self, $response_text) = @_;
    $response_text = substr($response_text, 1) if ($response_text =~ /^[+-]/);
    my @response = split(/[\s\,]/, $response_text);
    for my $response (@response) {
        if ($response =~ /^[xbc*]$/) {
            return 1;
        }
        if ($response !~ /^(\d+)([-\.]+(\d+))?$/) {
            $MESSAGE .= "\n" if ($MESSAGE);
            $MESSAGE .= "ERROR: Invalid list provided ($response)";
            return 0;
        }
        if ($3 && $1 && $3 < $1) {
            $MESSAGE .= "\n" if ($MESSAGE);
            $MESSAGE .= "ERROR: Inverted range provided ($1-$3)";
            return 0;
        }
    }
    return 1;
}

sub _trim_list_from_response {
    my ($self, $response_text, $param_name, @list) = @_;

    my $method;
    if ($response_text =~ /^[+-]/) {
        $method = substr($response_text, 0, 1);
        $response_text = substr($response_text, 1);
    }
    else {
        $method = '+';
    }

    my @response = split(/[\s\,]/, $response_text);
    my %indices;
    @indices{0..$#list} = 0..$#list if ($method eq '-');

    for my $response (@response) {
        $response =~ /^(\d+)([-\.]+(\d+))?$/;
        my $low = $1; $low--;
        my $high = $3 || $1; $high--;
        die if ($high < $low);
        if ($method eq '+') {
            @indices{$low..$high} = $low..$high;
        }
        else {
            delete @indices{$low..$high};
        }
    }
    #$self->debug_message("Indices: " . join(',', sort(keys %indices)));
    my @new_list = $self->_get_user_verification_for_param_value_drilldown($param_name, @list[sort keys %indices]);
    unless (@new_list) {
        @new_list = $self->_get_user_verification_for_param_value_drilldown($param_name, @list);
    }
    return @new_list;
}

sub _pad_string {
    my ($self, $str, $width, $pos) = @_;
    $str = '' if ! defined $str;
    my $padding = $width - length($str);
    $padding = 0 if ($padding < 0);
    if ($pos && $pos eq 'suffix') {
        return $str . ' 'x$padding;
    }
    else {
        return ' 'x$padding . $str;
    }
}

sub _can_interact_with_user {
    my $self = shift;
    if ( -t STDERR ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub _unique_elements {
    my ($self, @list) = @_;
    my %seen = ();
    my @unique = grep { ! $seen{$_} ++ } @list;
    return @unique;
}




1;


