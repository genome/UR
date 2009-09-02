

=head1 NAME

UR::Object::LegacySet::DefinitionType::Revisionable - a set with (potentially) multiple revision points

=head1 SYNOPSIS
 

    $s = GSC::DNA::Set->create(members => [$o1,$o2,$o3], revision_num => 1);
    $s->add_members($o4,$o5);
    print $s->revision_num;
    $s->new_revision(add_members => [$o6,$o7], revision_num => 2);
    $s->add_members($o8,$o9);
    $old_snapshot = $s1->get_revision(revision_num => 2);
    @new = $s->get_members;
    @old = $old_snapshot->get_members;
    

=head1 DESCRIPTION

Sets of this type track changes to their membership, each with a revision number.
By default the change point is set by the developer, who calls "new_revision"
and specifies a new revision number for the change.

Internally, sets of this type have another underlying set they delegate-to.  
When the new_revision() method is called, that set is duplicated and further 
changes go to the new delegate.

=cut

package UR::Object::LegacySet::DefinitionType::Revisionable;
use warnings;
use strict;
our $VERSION = '0.1';

use UR;
use GSC;

UR::Object::Type->define (
        class_name => __PACKAGE__,
        type_name => __PACKAGE__,
        inheritance => [qw/UR::Object::LegacySet/],
        properties => [qw/current_revision_id/]
    ) 
    or die ("Failed to make class metadata for " . __PACKAGE__);

# Override the constructor to do the right magic.

sub create {
    my $class = shift;
    my %params = @_;
    
    # get the parameters used by the revision snapshot/delegate set.
    my $current_revision_id = delete $params{current_revision_id};    
    my $revision_definition_type = delete $params{revision_definition_type};    
    my $revision_num = delete $params{revision_num};
    $revision_num ||= 1;
    
    # create this set, which will proxy to the current revision
    my $self = $class->SUPER::create(%params);    
    return unless $self;

    # construct or connect-to the current version delegate
    if (defined($current_revision_id)) {
        $self->current_revision_id($current_revision_id),
        $self->revision_num($revision_num);
    }
    else {
        my $delegate = $self->new_revision(
            definition_type => $revision_definition_type,
            revision_num => $revision_num
        );
    }
    
    return $self;
}

# Generate a new "current revision".

sub new_revision {
    my $self = shift;
    my %params = @_;    
    my $delegate_base_class = $self->member_class_name . "::Set";    
    my $revision_num = ($params{revision_num} || ($self->revision_num()+1));    
    my $previous_revision_set = $self->get_current_revision;
    
    my $delegate = $delegate_base_class->create(
        %params,         
        revision_num => $revision_num,        
        ($previous_revision_set ? (template => $previous_revision_set) : () )    
    );
    
    unless ($delegate) {
        $self->error_message(
            "Failed to create set revision \$revision_num snapshot: "
            . $delegate_base_class->error_message
        );
        return;
    }
    my $rv = $self->revision_num_class_name->create(
        reference_set_id => $self->id,
        revision_set_id => $delegate->id,
        revision_num => $revision_num
    );
    unless ($rv) {
        print $self->revision_num_class_name->error_message;
    }    
    $self->current_revision_id($delegate->id);
    return $delegate;
}

# Delegate to the current revision for all normal operations.

sub has_member_id {
    shift->get_current_revision->has_member_id(@_);
}

sub get_member_ids {
    shift->get_current_revision->get_member_ids(@_);
}

sub add_member_ids {
    shift->get_current_revision->add_member_ids(@_);
}

sub remove_member_ids {
    shift->get_current_revision->remove_member_ids(@_);
}

sub revision_num {
    shift->get_current_revision->revision_num(@_);
}

sub can {
    print "can @_\n";
    my $delegate = $_[0]->get_current_revision;
    my $r;
    if ($delegate) {
        $r = $delegate->can($_[1]);
    }
    else {
        $r = $_[0]->can("SUPER::" . $_[1]);
    }
    print "   ret $r\n";
    return $r;
}

sub AUTOSUB {
    my ($class,$func) = @_;
    print "c $class f $func @_\n";    
}

sub xadd_members {
    shift->get_current_revision->add_members(@_);
}

sub xremove_members {
    shift->get_current_revision->remove_members(@_);
}

# Interact with various revisions, including the current revision.

sub get_current_revision {
    my $self = shift;
    my $cr_id = $self->current_revision_id;
    return unless defined($cr_id);
    my $revision = $self->revision_class_name->get($cr_id);
}

sub get_revisions {
    my $self = shift;
    my %rev_ids = 
        map { $_->revision_set_id => $_->revision_num }
        $self->revision_num_class_name->get(
            reference_set_id => $self->id,
            @_
        );
    my @revisions = 
        sort { $rev_ids{$a->id} <=> $rev_ids{$b->id} }
        $self->revision_class_name->get(id => [keys %rev_ids]);
}

# Constant subclass metadata.

sub revision_class_name {
    shift->member_class_name . "::Set"
}

sub revision_num_class_name {
    #shift->revision_class_name . "::DefinitionMeta::Revision"
    "UR::Object::LegacySet::DefinitionMeta::Revision"
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
