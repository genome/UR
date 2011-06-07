package UR::Namespace::Command::Update::Doc;

use strict;
use warnings;

use UR;
use IO::File;
use File::Slurp     qw/write_file/;
use File::Basename  qw/dirname/;

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
        generate_index => {
            is => 'Boolean',
            default_value => 1,
            doc => "when true, an 'index' of all files generated is written (currently works for html only)",
        },
    ],
    has_transient_optional => [
        _writer_class => {
            is => 'Text',
        },
        _index_filename => {
            is => 'Text',
        }
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

    die "--generate-index requires --output-dir to be specified" if $self->generate_index and !$self->output_path;

    # scrub any trailing / from output_path
    if ($self->output_path) {
        my $output_path = $self->output_path;
        $output_path =~ s/\/+$//m;
        $self->output_path($output_path);
    }

    $self->_writer_class("UR::Doc::Writer::" . ucfirst($self->output_format));
    die "Unable to create a writer for output format '" . $self->output_format . "'" unless($self->_writer_class->can("create"));

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

    my @command_trees = map( $self->_get_command_tree($_), @targets);
    $self->_generate_index(@command_trees);
    for my $tree (@command_trees) {
        $self->_process_command_tree($tree);
    }

    return 1;
}

sub _generate_index {
    my ($self, @command_trees) = @_;

    if ($self->generate_index) {
        my $index = $self->_writer_class->generate_index(@command_trees);
        if ($index and $index ne '') {
            my $index_filename = $self->_make_filename("index");
            my $index_path = join("/", $self->output_path, $index_filename);
            if (-e $index_path) {
                $self->warning_message("Index generation overwriting existing file at $index_path");
            }
            write_file($index_path, \$index);
            $self->_index_filename($index_filename) if -e $index_path;
        } else {
            $self->warning_message("Unable to generate index");
        }
    }
    return;
}

sub _process_command_tree {
    my ($self, $tree) = @_;

    my $command = $tree->{command};
    my $doc;
    eval {
        my @sections = $command->doc_sections;
        my @navigation_info = $self->_navigation_info($command);
        my $writer = $self->_writer_class->create(
            sections => \@sections,
            title => $command->command_name,
            navigation => \@navigation_info,
        );
        $doc = $writer->render;
    };

    if($@) {
        $self->warning_message('Could not generate docs for ' . $command . '. ' . $@);
        return;
    }

    unless($doc) {
        $self->warning_message('No docs generated for ' . $command);
        return;
    }

    my $command_name = $command->command_name;
    my $filename = $self->_make_filename($command_name);
    my $dir = $self->_get_output_dir($command_name);
    my $doc_path = join("/", $dir, $filename);
    $self->status_message("Writing $doc_path");

    my $fh;
    $fh = IO::File->new('>' . $doc_path) || die "Cannot create file at " . $doc_path . "\n";
    print $fh $doc;
    close($fh);

    for my $subtree (@{$tree->{sub_commands}}) {
        $self->_process_command_tree($subtree);
    }
}

sub _make_filename {
    my ($self, $class_name) = @_;
    $class_name =~ s/ /-/g;
    return $class_name . "." . $self->output_format;
}

sub _get_output_dir {
    my ($self, $class_name) = @_;

    return $self->output_path if defined $self->output_path;
    return dirname($class_name->__meta__->module_path);
}

sub _navigation_info {
    my ($self, $cmd_class) = @_;

    my @navigation_info;
    if ($cmd_class eq $self->class_name) {
        push(@navigation_info, [$self->executable_name, undef]);
    } else {
        push(@navigation_info, [$cmd_class->command_name_brief, undef]);
        my $parent_class = $cmd_class->parent_command_class;
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
    }

    if ($self->_index_filename) {
        unshift(@navigation_info, ["(Top)", $self->_index_filename]);
    }

    return @navigation_info;
}

sub _get_command_tree {
    my ($self, $command) = @_;
    my $src = "use $command";
    eval $src;
    if ($@) {
        $self->error_message("Failed to load class $command: $@");
        return;
    } else {
        my $module_name = $command;
        $module_name =~ s|::|/|g;
        $module_name .= '.pm';
        $self->status_message("Loaded $command from $module_name at $INC{$module_name}\n");
    }

    my $tree = {
        command => $command,
        sub_commands => []
    };

    if ($command eq $self->class_name) {
        $tree->{command_name} = $tree->{command_name_brief} = $self->executable_name;
    } else {
        $tree->{command_name} = $command->command_name;
        $tree->{command_name_brief} = $command->command_name_brief;
    }

    $tree->{uri} = $self->_make_filename($tree->{command_name});

    if ($command->can("sub_command_classes")) {
        for my $cmd ($command->sub_command_classes) {
            my $subtree = $self->_get_command_tree($cmd);
            push(@{$tree->{sub_commands}}, $subtree) if $subtree;
        }
    }
    return $tree;
}

1;
