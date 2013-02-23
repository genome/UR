package above;

use strict;
use warnings;

our $VERSION = '0.02';

sub import {
    my $package = shift;
    for (@_) {
        use_package($_);
    }
}

our %used_libs;
BEGIN {
    %used_libs = ($ENV{PERL_USED_ABOVE} ? (map { $_ => 1 } split(":",$ENV{PERL_USED_ABOVE})) : ());
    for my $path (keys %used_libs) {
        #print STDERR "Using (parent process') libraries at $path\n";
        eval "use lib '$path';";
        die "Failed to use library path '$path' from the environment PERL_USED_ABOVE?: $@" if $@;
    }
};

sub use_package {
    my $class  = shift;
    my $caller = (caller(1))[0];
    my $module = $class;
    $module =~ s/::/\//g;
    $module .= ".pm";

    ## paths already found in %used_above have
    ## higher priority than paths based on cwd
    for my $path (keys %used_libs) {
        if (-e "$path/$module") {
            eval "package $caller; use $class";
            die $@ if $@;
            return;
        }
    }

    require Cwd;
    my $cwd = Cwd::cwd();
    my @parts = ($cwd =~ /\//g);
    my $dirs_above = scalar(@parts);
    my $path=$cwd.'/';
    until (-e "$path./$module") {
        if ($dirs_above == 0) {
            # Not found.  Use the one out under test.
            # When deployed.
            $path = "";
            last;
        };
        #print "Didn't find it in $path, trying higher\n";
        $path .= "../";
        $dirs_above--;
    }

    # Get the special path in place
    if (length($path)) {
        while ($path =~ s:/[^/]+/\.\./:/:) { 1 } # simplify
        unless ($used_libs{$path}) {
            print STDERR "Using libraries at $path\n" unless $ENV{PERL_ABOVE_QUIET} or $ENV{COMP_LINE};
            eval "use lib '$path';";
            die $@ if $@;
            $used_libs{$path} = 1;
            my $env_value = join(":",sort keys %used_libs);
            $ENV{PERL_USED_ABOVE} = $env_value;
        }
    }

    # Now use the module.
    eval "package $caller; use $class";
    die $@ if $@;

};

1;

=pod

=head1 NAME

above - auto "use lib" when a module is in the tree of the PWD 

=head1 SYNOPSIS

use above "My::Module";

=head1 DESCRIPTION

Used by the command-line wrappers for Command modules which are developer tools.

Do NOT use this in modules, or user applications.

Uses a module as though the cwd and each of its parent directories were at the beginnig of @INC.
If found in that path, the parent directory is kept as though by "use lib".

=head1 EXAMPLES

# given
/home/me/perlsrc/My/Module.pm

# in    
/home/me/perlsrc/My/Module/Some/Path/

# in myapp.pl:
use above "My::Module";

# does this ..if run anywhere under /home/me/perlsrc: 
use lib '/home/me/perlsrc/'
use My::Module;

=head1 AUTHOR

Scott Smith

=cut

