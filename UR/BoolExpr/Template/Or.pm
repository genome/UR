
=head1 NAME

UR::BoolExpr::Or - A rule which is true if any of a list of alternative rules are true

=head1 SYNOPSIS

=cut


package UR::BoolExpr::Template::Or;

use warnings;
use strict;
our $VERSION = '0.1';

require UR;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    is              => ['UR::BoolExpr::Template'],    
);


1;

=pod

=head1 PROPERTIES

=over 4

=item

=back

=head1 GENERAL METHODS

=over 4

=item 

=back

=head1 OBJECT-BASED MEMBERSHIP METHODS

=over 4

Report bugs to <software@watson.wustl.edu>.

=head1 SEE ALSO

App(3), UR::Object(3), UR::BoolExpr::DefinitionType::Manual(3),

=head1 AUTHOR

Scott Smith <ssmith@watson.wustl.edu>,

=cut


=cut


# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software.  You may distribute under the terms
# of either the GNU General Public License or the Artistic License, as
# specified in the Perl README file.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

# $Header: /var/lib/cvs/perl_modules/App/Object/Set.pm,v 1.8 2005/07/07 22:07:24 ssmith Exp $
