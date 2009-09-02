=head1 NAME

UR::Object::LegacySet::DefinitionMeta::Membership

=head1 SYNOPSIS
 
    print $m->set_id, "\n";
    print $m->member_id, "\n";

=head1 DESCRIPTION

 Sometimes used internally by UR::Object::LegacySet subclasses to resolve membership.

 Objects of this type represent explicit records of objects being in a set.

 An example set definition subclass using these to resolve membership is
 UR::Object::LegacySet::DefinitionType::Explicit.
 
=cut


package UR::Object::LegacySet::DefinitionMeta::Membership;

use warnings;
use strict;

use UR;
use GSC;

our $VERSION = '0.1';

UR::Object::Type->define(
    class_name => 'UR::Object::LegacySet::DefinitionMeta::Membership',
    id_properties => [qw/set_id member_id/],
    properties => [
        member_id                        => { type => '', len => undef },
        set_id                           => { type => '', len => undef },
    ],
);


1;

# A stored link between a set and a set member.
# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software.  You may distribute under the terms
# of either the GNU General Public License or the Artistic License, as
# specified in the Perl README file.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
