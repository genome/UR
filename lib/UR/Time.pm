package UR::Time;
use Date::Format qw/time2str/;


# UR now presumes that you are on NTP, and this module is really for backward compataiblity

sub now {
    return time2str('%Y-%m-%d %T',time);
}

=pod

=head1 NAME

UR::Time - backward-compatibility for sortable date/time strings

=head1 SYNOPSIS

  print UR::Time->now();
  2010-12-18 11:34:15

=head1 DESCRIPTION

This module returns the time as seen by the transaction system.

This was built around non NTP-serviced machines which
syncyronized time around the clock on a database.

It contains exactly one method, with one line of code, which is
smaller than this sentence.

=item now

  $date = UR::Time->now;

This method returns the current date/time in the default format.  This
method will attempt to get this time from the the database, if a
connection is available.

=back

=head1 SEE ALSO

Date::Format

=cut

1;

