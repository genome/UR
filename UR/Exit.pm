# Class to allow for smooth exits.
# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software.  You may distribute under the terms
# of either the GNU General Public License or the Artistic License, as
# specified in the Perl README file.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package UR::Exit;

=pod

=head1 NAME

UR::Exit - methods to allow clean application exits.

=head1 SYNOPSIS

  UR::Exit->exit_handler(\&mysub);

  UR::Exit->clean_exit($value);

=head1 DESCRIPTION

This module provides the ability to perform certain operations before
an application exits.

=cut

# set up module
require 5.6.0;
use warnings;
use strict;
our $VERSION = '0.1';
our (@ISA, @EXPORT, @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw();

use Carp;


=pod

=head1 METHODS

These methods provide exit functionality.

=over 4

=item exit_handler

  UR::Exit->exit_handler(\&mysub);

Specifies that a given subroutine be run when the application exits.
(Unimplimented!)

=cut
 
sub exit_handler
{
    die "Unimplimented";
}

=pod

=item clean_exit

  UR::Exit->clean_exit($value);

Exit the application, running all registered subroutines.
(Unimplimented!  Just exits the application directly.)

=cut

sub clean_exit 
{
    my $class = shift;
    my ($value) = @_;
    $value = 0 unless defined($value);
    exit($value);
}

=pod

=item death

Catch any die or warn calls.  This is a universal place to catch die
and warn if debugging.

=cut

sub death
{

    # workaround common error    
    if ($_[0] =~ /Can.*t upgrade that kind of scalar during global destruction/)
    {
        exit 1;
    }

    # check the call stack depth for up-stream evals
    # this handler is only to pretty-up things which AREN'T caught.
    my $call_stack_depth = 0;
    for (1) {
        my @details = caller($call_stack_depth);
        #print Data::Dumper::Dumper(\@details);
        last if scalar(@details) == 0;

        if ($details[1] =~ /\(eval .*\)/) {
            #print "<no carp due to eval string>";
            return;
        }
        elsif ($details[3] eq "(eval)") {
            #print "<no carp due to eval block>";
            return;
        }
        $call_stack_depth++;
        redo;
    }

    if 
    (
        $_[0] =~ /\n$/ 
        and UNIVERSAL::can("UR::Context::Process","is_initialized")
        and defined(UR::Context::Process->is_initialized)
        and (UR::Context::Process->is_initialized == 1)
    )
    {
        # Do normal death if there is a newline at the end, and all other
        # things are sane.
        return;
    }
    else
    {
        # Dump the call stack in other cases.
        # This is a developer error occurring while things are
        # initializing.
        Carp::cluck(@_);
	return;
    }
}

=pod

=item warning

Give more informative warnings.

=cut

sub warning
{
    return if $_[0] =~ /Attempt to free unreferenced scalar/;
    return if $_[0] =~ /Use of uninitialized value in exit at/;
    return if $_[0] =~ /Use of uninitialized value in subroutine entry at/;    
    return if $_[0] =~ /One or more DATA sections were not processed by Inline/;
    UR::ModuleBase->warning_message(@_);
    if ($_[0] =~ /Deep recursion on subroutine/)
    {
        print STDERR "Forced exit by App.pm on deep recursion.\n";
        my @stack = split(/\n/,Carp::longmess());
        print STDERR "Stack tail:\n@stack\n";
        exit 1;
    }
    return;
}

$SIG{__DIE__} = \&death unless ($SIG{__DIE__});
$SIG{__WARN__} = \&warning unless ($SIG{__WARN__});

1;
__END__

=pod

=back

=head1 BUGS

Report bugs to <software@watson.wustl.edu>.

=head1 SEE ALSO

UR(3), Carp(3)

=head1 AUTHOR

Scott Smith <ssmith@watson.wustl.edu>

=cut

#$Header$

