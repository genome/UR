package UR::Namespace::Command::Update::TabCompletionSpec;

use strict;
use warnings;

use UR;
use Getopt::Complete;
use Getopt::Complete::Cache;
use IO::File;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command',
    has => [
        classname => {
            is => 'Text',
            shell_args_position => 1,
            doc => 'The base class to use as trunk of command tree, e.g. UR::Namespace::Command',
        },
        output => {
            is => 'Text',
            is_optional => 1,
            doc => 'Override output location of the opts spec file.',
        },
    ]
);


sub help_brief {
    "Creates a .opts file beside class/module passed as argument, e.g. UR::Namespace::Command.";
}

sub is_sub_command_delegator { 0; }

sub execute {
    my $self = shift;
    my $class = $self->classname;
    
    eval "use above '$class';";
    if ($@) {
        $self->error_message("Unable to use above $class.\n$@");
        return;
    }

    (my $module_path) = Getopt::Complete::Cache->module_and_cache_paths_for_package($class, 1);
    my $cache_path = $module_path . ".opts";
    unless ($self->output) {
        $self->output($cache_path);
    }
    $self->status_message("Generating " . $self->output . " file for $class.");
    $self->status_message("This may take some time and may generate harmless warnings...");

    my $fh;
    $fh = IO::File->new('>' . $self->output) || die "Cannot create file at " . $self->output . "\n";
    
    if ($fh) {
        my $src = Data::Dumper::Dumper($class->resolve_option_completion_spec());
        $src =~ s/^\$VAR1/\$$class\:\:OPTS_SPEC/;
        $fh->print($src);
    }
    print "\nOPTS_SPEC file created at $cache_path\n";
}

1;
