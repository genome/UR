
=head1 NAME

UR::Object::LegacySet::DefinitionType::Manual - A set subclass for sets with explicitly defined members.

=head1 SYNOPSIS
 

    $s1 = GSC::DNA::Set->create(members => [$o1,$o2,$o3]);
    $s1->add_members($o4,$o5);
    die unless $s1->has_member($o4);
    @o = $s1->get_members; 
    $s1->remove_members($o2,$o4);
    $s1->delete; 

=head1 DESCRIPTION

This is the simplest set definition.  All control is explicitly in the hands
of the developer.  Add or remove objects manually, and get back a list which
does not repeat, and does not maintain order.

The ID-based methods are implimented here as required by UR::Object::LegacySet.
Membership is recorded explicitly via UR::Object::LegacySet::DefinitionMeta::Membership

Everything else is inherited default data-set functionality.

=cut

package UR::Object::LegacySet::DefinitionType::Manual;

use warnings;
use strict;
use UR;
use GSC;

UR::Object::Type->define(
    class_name => 'UR::Object::LegacySet::DefinitionType::Manual',
    is => ['UR::Object::LegacySet'],
);

our $VERSION = '0.1';

# Override the constructor to support defining the set members at creation time.

sub create {
    my $class = shift;
    my %params = @_;
    my $members = delete $params{members};
    my $member_ids = delete $params{member_ids};
    my $template = $params{template};
    if ((defined($members) + defined($member_ids) + defined($template)) > 1) {
        die "Both explicit memberes and a template supplied to create()!"
    }
    my $self = $class->SUPER::create(%params);
    return unless $self;
    if ($members) {
        $self->add_members(@$members)
    }
    elsif ($member_ids) {
        $self->add_member_ids(@$member_ids)
    }
    if ($template) {
        $self->add_members_ids($template->get_member_ids)
    }
    return $self;
}

# The ID-based interface to the set is required.
# The object-based interface is inherited, as are the default operation methods.

sub has_member_id {
    my $self = shift;
    my $set_id = $self->id;
    my $meta_member_class_name = $self->meta_member_class_name;
    my $found = $meta_member_class_name->get(set_id => $set_id, member_id => $_[0]);
    return ($found ? 1 : 0);    
}

sub get_member_ids {
    my $self = shift;    
    my $set_id = $self->id;
    my $meta_member_class_name = $self->meta_member_class_name;
    my @ids = map { $_->member_id } $meta_member_class_name->get(set_id => $set_id);
    return @ids;
}

# Adding and removing members via direct method call is specific to manual sets.

sub add_members {
    my $self = shift;
    my $member_class_name = $self->member_class_name; 
    my @ids = 
        map { 
            die unless $_->isa($member_class_name);
            $_->id;
        } @_;
    return $self->add_member_ids(@ids);
}

sub add_member_ids {
    my $self = shift;
    my $set_id = $self->id;
    my $meta_member_class_name = $self->meta_member_class_name;
    my @add;
    for my $new_member_id (@_) {        
        if ($meta_member_class_name->create(set_id => $set_id, member_id => $new_member_id)) {            
            push @add, $new_member_id;
        }
    }
    $self->signal_change("add_member_ids",\@add);
    return scalar(@add);
}

sub remove_members {
    my $self = shift;    
    my @obj = @_;
    my @ids = map { $_->id } @obj;
    return $self->remove_member_ids(@ids);
}

sub remove_member_ids {
    my $self = shift;    
    my @ids = @_;
    my $set_id = $self->id;
    my $member_class_name = $self->member_class_name; 
    my $meta_member_class_name = $self->meta_member_class_name;
    my @remove = $meta_member_class_name->get(set_id => $set_id, member_id => \@ids);    
    for (@remove) {
        $_->delete
    }
    $self->signal_change("remove_member_ids", \@remove);
    return scalar(@remove);
}


1;

# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software.  You may distribute under the terms
# of either the GNU General Public License or the Artistic License, as
# specified in the Perl README file.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

#$Header$
