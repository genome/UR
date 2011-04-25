package UR::Namespace::Command::Update::TabCompletionSpec;

use strict;
use warnings;

use UR;
our $VERSION = "0.31"; # UR $VERSION;
use IO::File;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command::Base',
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
   
    eval {
        require Getopt::Complete;
        require Getopt::Complete::Cache;
    };
    if ($@) {
        die "Errors using Getopt::Complete.  Do you have Getopt::Complete installed?  If not try 'cpanm Getopt::Complete'";
    }

    eval "use above '$class';";
    if ($@) {
        $self->error_message("Unable to use above $class.\n$@");
        return;
    }

    (my $module_path) = Getopt::Complete::Cache->module_and_cache_paths_for_package($class, 1);
    my $cache_path = $module_path . ".opts";
    if (-s $cache_path) {
        rename($cache_path, "$cache_path.bak");
    }
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
    if (-s $cache_path) {
        print "\nOPTS_SPEC file created at $cache_path\n";
        unlink("$cache_path.bak");
    } else {
        if (-s "$cache_path.bak") {
            print "\nERROR: $cache_path is 0 bytes, reverting to previous\n";
            rename("$cache_path.bak", $cache_path);
        } else {
            print "\nERROR: $cache_path is 0 bytes and no backup exists, removing file\n";
            unlink($cache_path);
        }
    }
}

1;
