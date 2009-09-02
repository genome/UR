
package UR::Command::Redescribe;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Command::RunsOnModulesInTree',
);

sub help_brief {
    "Outputs class description(s) formatted to the latest standard."
}

sub for_each_class_object {
    my $self = shift;
    my $class = shift;
    my $src = $class->resolve_module_header_source;
    if ($src) {
        print $src, "\n";
        return 1;
    }
    else {
        print STDERR "No source for $class!";
        return;
    }
}

1;

