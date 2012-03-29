package UR::All;

use strict;
use warnings;

our $VERSION = "0.38"; # UR $VERSION;

BEGIN { require above; };
use UR;

my $dir = $INC{"UR.pm"};
$dir = File::Basename::dirname($dir);

my @src = 
    map { chomp $_; s|/|::|g; s/.pm//; "use $_;" }
    sort
    grep { /.pm$/ }
    `cd $dir; find *`; 

for my $src (@src) {
    eval $src;
    if ($@) {
        die "failed to compile: $src\n$@\n";
    }
}

1;

__END__

=pod

=head1 NAME

UR::All

=head1 SYNOPSIS

 use UR::All;

=head1 DESCRIPTION

This module exists to let software preload everything in the distribution

It is slower than "use UR", but is good for things like FastCGI servers.

=cut
