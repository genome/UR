#!/usr/bin/env perl
my $new = shift;
die "please supply the new version number N.NN\n" unless $new;
my $old = shift;
$old ||= ($new - 0.01);
print "updating version from $old to $new\n";
my $cmd = qq{cd ..; dist-maint/findreplace '$old"; # UR \\\$VERSION' '$new"; # UR \$VERSION' `grep -rn '# UR \\\$VERSION' lib/ | sed s/:.*//`};
print $cmd,"\n";
system $cmd;

