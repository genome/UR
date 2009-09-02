
package UR::Command::Commit;

use strict;
use warnings;

use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is =>'UR::Command::RunsOnModulesInTree',
);

sub help_brief {
    "Synchronizes class schema changes to the database schema.  (NOT IMPLEMENTED)"
}

sub for_each_class_object {
    my $self = shift;
    my $class = shift;
    print STDERR "Writing DDL to update the database schema from the class is not implemented.  Update " . __PACKAGE__ . "\n";
    return;
}

1;
