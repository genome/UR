package Command::Tree;

use strict;
use warnings;
use UR;
use File::Basename qw/basename/;

our $VERSION = "0.29"; # UR $VERSION;

class Command::Tree {
    is => 'Command::V2',
    is_abstract => 1,
    doc => 'base class for commands which delegate to sub-commands',
};


sub _execute_with_shell_params_and_return_exit_code {
    my $class = shift;
    my @argv = @_;

    # make --foo=bar equivalent to --foo bar
    @argv = map { ($_ =~ /^(--\w+?)\=(.*)/) ? ($1,$2) : ($_) } @argv;
    my ($delegate_class, $params) = $class->resolve_class_and_params_for_argv(@argv);

    my $rv = $class->_execute_delegate_class_with_params($delegate_class,$params);
    
    my $exit_code = $delegate_class->exit_code_for_return_value($rv);
    return $exit_code;
}

sub resolve_class_and_params_for_argv {
    # This is used by execute_with_shell_params_and_exit, but might be used within an application.
    my $self = shift;
    my @argv = @_;

    if ( $argv[0] and $argv[0] !~ /^\-/ 
            and my $class_for_sub_command = $self->class_for_sub_command($argv[0]) ) {
        # delegate
        shift @argv;
        return $class_for_sub_command->resolve_class_and_params_for_argv(@argv);
    }
    else {
        return ($self,undef);
    }
}

sub _execute_delegate_class_with_params {
    # this is called by both the shell dispatcher and http dispatcher for now
    my ($class, $delegate_class, $params) = @_;

    $delegate_class->dump_status_messages(1);
    $delegate_class->dump_warning_messages(1);
    $delegate_class->dump_error_messages(1);
    $delegate_class->dump_debug_messages(0);

    unless ($delegate_class) {
        $class->usage_message($class->help_usage_complete_text);
        return;
    }

    if ( $delegate_class->is_sub_command_delegator && !defined($params) ) {
        my $command_name = $delegate_class->command_name;
        $delegate_class->status_message($delegate_class->help_usage_complete_text);
        $delegate_class->error_message("Please specify a valid sub-command for '$command_name'.");
        return;
    }
    if ( $params->{help} ) {
        $delegate_class->usage_message($delegate_class->help_usage_complete_text);
        return;
    }

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

    if ($command_object->__errors__) {
        $command_object->delete;
    }

    return $rv;
}


sub help_brief {
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
        return "";
    }
}

sub is_sub_command_delegator {
    return 1;
}

sub resolve_option_completion_spec {
    my $class = shift;
    my @completion_spec;

    my @sub = eval { $class->sub_command_names};
    if ($@) {
        $class->warning_message("Couldn't load class $class: $@\nSkipping $class...");
        return;
    }
    for my $sub (@sub) {
        my $sub_class = $class->class_for_sub_command($sub);
        my $sub_tree = $sub_class->resolve_option_completion_spec() if defined($sub_class);

        # Hack to fix several broken commands, this should be removed once commands are fixed.
        # If the commands were not broken then $sub_tree will always exist.
        # Basically if $sub_tree is undef then we need to remove '>' to not break the OPTS_SPEC
        if ($sub_tree) {
            push @completion_spec, '>' . $sub => $sub_tree;
        }
        else {
            print "WARNING: $sub has sub_class $sub_class of ($class) but could not resolve option completion spec for it.\n".
                    "Setting $sub to non-delegating command, investigate to correct tab completion.\n";
            push @completion_spec, $sub => undef;
        }
    }
    push @completion_spec, "help!" => undef;

    return \@completion_spec
}

sub help_usage_complete_text {
    my $self = shift;

    my $command_name = $self->command_name;
    my $text;
    
    # show the list of sub-commands
    $text = sprintf(
        "Sub-commands for %s:\n%s",
        Term::ANSIColor::colored($command_name, 'bold'),
        $self->help_sub_commands,
    );

    return $text;
}

sub help_usage_command_pod {
    my $self = shift;

    my $command_name = $self->command_name;
    my $pod;

    # standard: update this to do the old --help format
    my $synopsis = $self->command_name . ' ' . $self->_shell_args_usage_string . "\n\n" . $self->help_synopsis;
    my $required_args = $self->help_options(is_optional => 0, format => "pod");
    my $optional_args = $self->help_options(is_optional => 1, format => "pod");
    my $sub_commands = $self->help_sub_commands(brief => 1) if $self->is_sub_command_delegator;
    my $help_brief = $self->help_brief;
    my $version = do { no strict; ${ $self->class . '::VERSION' } };

    $pod =
        "\n=pod"
        . "\n\n=head1 NAME"
        .  "\n\n"
        .   $self->command_name 
        . ($help_brief ? " - " . $self->help_brief : '') 
        . "\n\n";

    if ($version) {
        $pod .=
            "\n\n=head1 VERSION"
            . "\n\n"
            . "This document " # separated to trick the version updater 
            . "describes " . $self->command_name . " version " . $version . '.'
            . "\n\n";
    }

    if ($sub_commands) {
        $pod .=
                (
                    $sub_commands
                    ? "=head1 SUB-COMMANDS\n\n" . $sub_commands . "\n\n"
                    : ''
                )
    }
    else {
        $pod .=
                (
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
            . "\n";
    }
    
    $pod .= "\n\n=cut\n\n";

    return "\n$pod";
}

sub sorted_sub_command_classes {
    no warnings;
    my @c = shift->sub_command_classes;
    return sort {
            ($a->sub_command_sort_position <=> $b->sub_command_sort_position)
            ||
            ($a->sub_command_sort_position cmp $b->sub_command_sort_position)
        } 
        @c;
}

sub sorted_sub_command_names {
    my $class = shift;
    my @sub_command_classes = $class->sorted_sub_command_classes;
    my @sub_command_names = map { $_->command_name_brief } @sub_command_classes;
    return @sub_command_names;
}

sub sub_commands_table {
    my $class = shift;
    my @sub_command_names = $class->sorted_sub_command_names;

    my $max_length = 0;
    for (@sub_command_names) {
        $max_length = length($_) if ($max_length < length($_));
    }
    $max_length ||= 79;
    my $col_spacer = '_'x$max_length;

    my $n_cols = floor(80/$max_length);
    my $n_rows = ceil(@sub_command_names/$n_cols);
    my @tb_rows;
    for (my $i = 0; $i < @sub_command_names; $i += $n_cols) {
        my $end = $i + $n_cols - 1;
        $end = $#sub_command_names if ($end > $#sub_command_names);
        push @tb_rows, [@sub_command_names[$i..$end]];
    }
    my @col_alignment;
    for (my $i = 0; $i < $n_cols; $i++) {
        push @col_alignment, { sample => "&$col_spacer" };
    }
    my $tb = Text::Table->new(@col_alignment);
    $tb->load(@tb_rows);
    return $tb;
}

sub help_sub_commands {
    my $class = shift;
    my %params = @_;
    my $command_name_method = 'command_name_brief';
    #my $command_name_method = ($params{brief} ? 'command_name_brief' : 'command_name');
    
    my @sub_command_classes = $class->sorted_sub_command_classes;

    my %categories;
    my @categories;
    for my $sub_command_class (@sub_command_classes) {
        my $category = $sub_command_class->sub_command_category;
        $category = '' if not defined $category;
        next if $sub_command_class->_is_hidden_in_docs();
        my $sub_commands_within_category = $categories{$category};
        unless ($sub_commands_within_category) {
            if (defined $category and length $category) {
                push @categories, $category;
            }
            else {
                unshift @categories,''; 
            }
            $sub_commands_within_category = $categories{$category} = [];
        }
        push @$sub_commands_within_category,$sub_command_class;
    }

    no warnings;
    local  $Text::Wrap::columns = 60;
    
    my $full_text = '';
    my @full_data;
    for my $category (@categories) {
        my $sub_commands_within_this_category = $categories{$category};
        my @data = map {
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
            @$sub_commands_within_this_category;

        if ($category) {
            # add a space between categories
            push @full_data, ['','',''] if @full_data;

            if ($category =~ /\D/) {
                # non-numeric categories show their category as a header
                $category .= ':' if $category =~ /\S/;
                push @full_data, 
                    [
                        Term::ANSIColor::colored(uc($category), 'blue'),
                        '',
                        ''
                    ];

            }
            else {
                # numeric categories just sort
            }
        }

        push @full_data, @data;
    }

    my @max_width_found = (0,0,0);
    for (@full_data) {
        for my $c (0..2) {
            $max_width_found[$c] = length($_->[$c]) if $max_width_found[$c] < length($_->[$c]);
        }
    }

    my @colors = (qw/ red   bold /);
    my $text = '';
    for my $row (@full_data) {
        for my $c (0..2) {
            $text .= ' ';
            $text .= Term::ANSIColor::colored($row->[$c], $colors[$c]),
            $text .= ' ';
            $text .= ' ' x ($max_width_found[$c]-length($row->[$c]));
        }
        $text .= "\n";
    }
    $DB::single = 1;        
    return $text;
}

#
# The following methods build allow a command to determine its 
# sub-commands, if there are any.
#

# This is for cases in which the Foo::Bar command delegates to
# Foo::Bar::Baz, Foo::Bar::Buz or Foo::Bar::Doh, depending on its paramters.

sub sub_command_dirs {
    my $class = shift;
    my $subdir = ref($class) || $class;
    $subdir =~ s|::|\/|g;
    my @dirs = grep { -d $_ } map { $_ . '/' . $subdir  } @INC;
    return @dirs;
}

sub sub_command_classes {
    my $class = shift;
    my $mapping = $class->_build_sub_command_mapping;
    return values %$mapping;
}

sub _build_sub_command_mapping {
    my $class = shift;
    $class = ref($class) || $class;
    
    my $mapping;
    do {
        no strict 'refs';
        $mapping = ${ $class . '::SUB_COMMAND_MAPPING'};
    };
    
    unless (ref($mapping) eq 'HASH') {
        my $subdir = $class; 
        $subdir =~ s|::|\/|g;

        for my $lib (@INC) {
            my $subdir_full_path = $lib . '/' . $subdir;
            next unless -d $subdir_full_path;
            my @files = glob($subdir_full_path . '/*');
            next unless @files;
            for my $file (@files) {
                my $basename = basename($file);
                $basename =~ s/.pm$//;
                my $sub_command_class_name = $class . '::' . $basename;
                my $sub_command_class_meta = UR::Object::Type->get($sub_command_class_name);
                unless ($sub_command_class_meta) {
                    local $SIG{__DIE__};
                    local $SIG{__WARN__};
                    # until _use_safe is refactored to be permissive, use directly...
                    eval "use $sub_command_class_name";
                }
                $sub_command_class_meta = UR::Object::Type->get($sub_command_class_name);
                next unless $sub_command_class_name->isa("Command");
                next if $sub_command_class_meta->is_abstract;
                my $name = $class->_command_name_for_class_word($basename); 
                $mapping->{$name} = $sub_command_class_name;
            }
        }
    }
    return $mapping;
}

sub sub_command_names {
    my $class = shift;
    my $mapping = $class->_build_sub_command_mapping;
    return keys %$mapping;
}

sub class_for_sub_command {
    my $self = shift;
    my $class = ref($self) || $self;
    my $sub_command = shift;

    return if $sub_command =~ /^\-/;

    my $mapping = $class->_build_sub_command_mapping;
    if (my $sub_command_class = $mapping->{$sub_command}) {
        return $sub_command_class;
    }


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


1;

__END__

=pod

=head1 NAME

Command::Tree -base class for commands which delegate to a list of sub-commands 

=head1 DESCRIPTION

# in Foo.pm
class Foo { is => 'Command::Tree' };

# in Foo/Cmd1.pm
class Foo::Cmd1 { is => 'Command' };

# in Foo/Cmd2.pm
class Foo::Cmd2 { is => 'Command' };

# in the shell
$ foo
cmd1
cmd2
$ foo cmd1
$ foo cmd2

=cut

