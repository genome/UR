
package UR::Namespace::Command::Diff;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Namespace::Command", # sub-commands inherit from UR::Namespace::Command::RunsOnModulesInTree
);

sub help_brief {
    "Show a diff for various kinds of other ur commands."
}

sub for_each_class_object_delegate_used_by_sub_commands {
    my $self = shift;
    my $class = shift;
    my $old = $class->module_header_source;
    my $new = $class->resolve_module_header_source;
    unless ($old eq $new) {
        print $class->class_name . ":\n";
        IO::File->new(">/tmp/diff1")->print($old);
        IO::File->new(">/tmp/diff2")->print($new);
        system "diff /tmp/diff1 /tmp/diff2";
        unlink "/tmp/diff1";
        unlink "/tmp/diff2";
    }
}

1;

