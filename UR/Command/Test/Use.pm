
package UR::Command::Test::Use;

use strict;
use warnings;
use UR;
use Cwd;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command::RunsOnModulesInTree",
    has => [
        verbose => { type => 'Boolean', doc => 'List each explicitly.' }
    ]
);

sub help_brief {
    "Tests each module for compile errors by 'use'-ing it."
}

sub help_synopsis {
    return <<EOS
ur test use         

ur test use Some::Module Some::Other::Module

ur test use ./Module.pm Other/Module.pm
EOS
}

sub help_detail {
    my $self = shift;
    my $text = <<EOS;

Tests each module by "use"-ing it.  Failures are reported individually.

Successes are only reported individualy if the --verbose option is specified.

A count of total successes/failures is returned as a summary in all cases.

EOS
    $text .= $self->_help_detail_footer;
    return $text;
}

sub before {
    my $self = shift;
    $self->{success} = 0;
    $self->{failure} = 0;
    $self->SUPER::before(@_);
}

sub for_each_module_file {
    my $self = shift;
    my $module_file = shift;
    eval "require '$module_file'";
    if ($@) {
        print "$module_file  FAILED:\n$@\n";
        $self->{failure}++;
    }
    else {
        print "$module_file  OK\n" if $self->verbose;
        $self->{success}++;
    }
    return 1;
}

sub after {
    my $self = shift;
    $self->status_message("SUCCESS: $self->{success}");
    $self->status_message("FAILURE: $self->{failure}");
}

1;

