package UR::Namespace::Command::Update::Pod;

use strict;
use warnings;

use UR;
our $VERSION = "0.27"; # UR $VERSION;
use IO::File;

class UR::Namespace::Command::Update::Pod {
    is => ['UR::Namespace::Command'],
    has => [
        base_commands => {
            is => 'Text',
            is_many => 1,
            shell_args_position => 1,
            doc => 'Generate documentation for these command modules and any subcommand modules'
        },
        output_path => {
            is => 'Text',
            is_optional => 1,
            doc => 'Location to output .pod files',
        },
    ],
    doc => "Generate POD documentation for commands."
};

sub help_brief {
    __PACKAGE__->__meta__->doc
}

sub help_synopsis{
    return <<"EOS"
ur update pod --output-path ./pod/ UR::Namespace::Command::Update
ur update pod --output-path ./pod/ UR::Namespace::Command::Update::ClassesFromDb UR::Namespace::Command::Update::RenameClass
EOS
}

sub help_detail {
    return join("\n", 
        'This tool generates POD documentation for each command.',
        'This command must be run from within the namespace directory.');
}

sub execute {
    my $self = shift;

    my @base_commands = $self->base_commands;
    @base_commands = $self->_class_names_in_tree(@base_commands);

    my @commands = map( $self->get_all_subcommands($_), @base_commands);
    push @commands, @base_commands;

    for my $command (@commands) {
        my $pod;
        eval {
            $pod = $command->help_usage_command_pod;
        };

        if($@) {
            $self->warning_message('Could not generate POD for ' . $command . '. ' . $@);
            next;
        }

        unless($pod) {
            $self->warning_message('No POD generated for ' . $command);
            next;
        }

        my $pod_path;
        if (defined $self->output_path) {
          my $filename = $command->command_name . '.pod';
          $filename =~ s/ /-/g;
          $pod_path = join('/', $self->output_path, $filename);
        } else {
          $pod_path = $command->__meta__->module_path;
          $pod_path =~ s/.pm/.pod/;
        }

        my $fh;
        $fh = IO::File->new('>' . $pod_path) || die "Cannot create file at " . $pod_path . "\n";
        print $fh $pod;
        close($fh);
    }

    return 1;
}

sub get_all_subcommands {
    my $self = shift;
    my $command = shift;

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
