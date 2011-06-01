package UR::Namespace::Command::Update::Doc;

use strict;
use warnings;

use UR;
use IO::File;

class UR::Namespace::Command::Update::Doc {
    is => 'Command::V2',
    has => [
        executable_name => {
            is => 'Text',
            shell_args_position => 1,
            doc => 'the name of the executable to document'
        },
        class_name => {
            is => 'Text',
            shell_args_position => 2,
            doc => 'the command class which maps to the executable'
        },
        targets => {
            is => 'Text',
            is_optional => 1,
            shell_args_position => 3,
            is_many => 1,
            doc => 'specific classes to document (documents all unless specified)',
        },
        input_path => {
            is => 'Path',
            is_optional => 1,
            doc => 'optional location of the modules to document',
        },
        output_path => {
            is => 'Text',
            is_optional => 1,
            doc => 'optional location to output documentation files',
        },
        output_format => {
            is => 'Text',
            default_value => 'pod',
            valid_values => ['pod', 'html'],
            doc => 'the output format to write'
        },
    ],
    doc => "generate documentation for commands"
};

sub help_synopsis {
    return <<"EOS"
ur update doc -i ./lib -o ./doc ur UR::Namespace::Command
EOS
}

sub help_detail {
    return join("\n", 
        'This tool generates documentation for each of the commands in a tree for a given executable.',
        'This command must be run from within the namespace directory.');
}

sub execute {
    my $self = shift;

    local $ENV{ANSI_COLORS_DISABLED}    = 1;
    my $entry_point_bin     = $self->executable_name;
    my $entry_point_class   = $self->class_name;

    my @targets = $self->targets;
    unless (@targets) {
        @targets = ($entry_point_class);
    }

    local @INC = @INC;
    if ($self->input_path) {
        unshift @INC, $self->input_path;
        $self->status_message("using modules at " . $self->input_path);
    }

    my $errors = 0;
    for my $target (@targets) {
        eval "use $target";
        if ($@) {
            $self->error_message("Failed to use $target: $@");
            $errors++;
        }
    }
    return if $errors;

    my @commands = map( $self->get_all_subcommands($_), @targets);
    push @commands, @targets;

    if ($self->output_path) {
        unless (-d $self->output_path) {
            if (-e $self->output_path) {
                $self->status_message("output path is not a directory!: " . $self->output_path);
            }
            else {
                mkdir $self->output_path;
                if (-d $self->output_path) {
                    $self->status_message("using output directory " . $self->output_path);
                }
                else {
                    $self->status_message("error creating directory: $! for " . $self->output_path);
                }
            }
        }
    }

    local $Command::V1::entry_point_bin = $entry_point_bin;
    local $Command::V2::entry_point_bin = $entry_point_bin;
    local $Command::V1::entry_point_class = $entry_point_class;
    local $Command::V2::entry_point_class = $entry_point_class;

    my $writer_class = "UR::Doc::Writer::" . ucfirst($self->output_format);

    for my $command (@commands) {
        my $doc;
        eval {
            my @sections = $command->doc_sections;
            my @navigation_info = $self->_navigation_info($command);
            my $writer = $writer_class->create(
                sections => \@sections,
                title => $command->command_name,
                navigation => \@navigation_info,
            );
            $doc = $writer->render;
        };

        if($@) {
            $self->warning_message('Could not generate docs for ' . $command . '. ' . $@);
            next;
        }

        unless($doc) {
            $self->warning_message('No docs generated for ' . $command);
            next;
        }

        my $doc_path;
        my $extension = '.'.$self->output_format;
        if (defined $self->output_path) {
          my $filename = $self->_make_filename($command->command_name) . $extension;
          my $output_path = $self->output_path;
          $output_path =~ s|/+$||m;          
          $doc_path = join('/', $output_path, $filename);
        } else {
          $doc_path = $command->__meta__->module_path;
          $doc_path =~ s/.pm/$extension/;
        }

        $self->status_message("Writing $doc_path");

        my $fh;
        $fh = IO::File->new('>' . $doc_path) || die "Cannot create file at " . $doc_path . "\n";
        print $fh $doc;
        close($fh);
    }

    return 1;
}

sub _make_filename {
    my ($self, $class_name) = @_;
    $class_name =~ s/ /-/g;
    return $class_name;
}

sub _navigation_info {
    my ($self, $cmd_class) = @_;

    return [$cmd_class->command_name, undef] if $cmd_class eq $self->class_name;

    my $parent_class = $cmd_class->parent_command_class;
    my @navigation_info;
    while ($parent_class) {
        if ($parent_class eq $self->class_name) {
            my $uri = $self->_make_filename($self->executable_name);
            my $name = $self->executable_name;
            unshift(@navigation_info, [$name, $uri]);
            last;
        } else {
            my $uri = $self->_make_filename($parent_class->command_name);
            my $name = $parent_class->command_name_brief;
            unshift(@navigation_info, [$name, $uri]);
        }
        $parent_class = $parent_class->parent_command_class;
    }
    push(@navigation_info, [$cmd_class->command_name_brief, undef]);

    return @navigation_info;
}

sub get_all_subcommands {
    my $self = shift;
    my $command = shift;
    my $src = "use $command";
    eval $src;

    if ($@) {
        $self->error_message("Failed to load class $command: $@");
    }
    else {
        my $module_name = $command;
        $module_name =~ s|::|/|g;
        $module_name .= '.pm';
        $self->status_message("Loaded $command from $module_name at $INC{$module_name}\n");
    }

    return unless $command->can("sub_command_classes");
    my @subcommands;
    eval {
        @subcommands = $command->sub_command_classes;
    };

    if($@) {
        $self->warning_message("Error getting subclasses for module $command: " . $@);
    }

    return unless @subcommands and $subcommands[0]; #Sometimes sub_command_classes returns 0 instead of the empty list

    return map($self->get_all_subcommands($_), @subcommands), @subcommands;
}

1;
