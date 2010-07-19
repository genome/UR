package UR::Namespace::Command::CreateCompletionSpecFile;

use strict;
use warnings;

use UR;
use Getopt::Complete;
use Getopt::Complete::Cache;
use above 'Genome';
use IO::File;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command',
    has => [
        classname => {
            shell_args_position => 1,
            doc => 'The base class to use as trunk of command tree, e.g. Genome::Command or Genome::Model::Tools',
        }
    ]
);


sub help_brief {
    "Creates a .opts file beside class/module passed as argument, e.g. Genome::Command.";
}

sub is_sub_command_delegator { 0; }

sub execute {
    my($self, $params) = @_;
    my $class = $params->{'classname'};

    (my $module_path) = Getopt::Complete::Cache->module_and_cache_paths_for_package($class, 1);
    my $cache_path = $module_path . ".opts";

    my $fh = IO::File->new('>' . $cache_path) || die "Cannot create file at $cache_path";
    if ($fh) {
        my $src = Data::Dumper::Dumper($class->resolve_option_completion_spec());
        $src =~ s/^\$VAR1/\$$class\:\:OPTS_SPEC/;
        $fh->print($src);
    }
    print "\nOPTS_SPEC file created at $cache_path\n" if $ENV{COMP_LINE};
}

1;
