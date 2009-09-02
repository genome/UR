
=head1 NAME

UR::Object::LegacySet::DefinitionType::Parameterized - A set subclass for sets with explicitly defined members.

=head1 SYNOPSIS
 

    $s = GSC::Clone::Set->create(
        params => {
            clone_status => 'active',
            chromosome => [2,4,7],
            clone_name => {   
                operator => 'like',
                value => 'SK%'
            }
        }
    );    
    @o1 = $s->get_members;    
    GSC::Clone->create(
        clone_name => 'SKXXXX', 
        clone_status => 'active', 
        chromosome => 7
    );
    @o2 = $s->get_members;
    die unless (@o2 = @o1+1);

=head1 DESCRIPTION

This is the simplest set definition.  All control is explicitly in the hands
of the developer.  Add or remove objects manually, and get back a list which
does not repeat, and does not maintain order.

The ID-based methods are implimented here as required by UR::Object::LegacySet.
Membership is recorded explicitly via UR::Object::LegacySet::Stored::Membership.

Everything else is inherited default set functionality.

=cut

package UR::Object::LegacySet::DefinitionType::Parameterized;
use warnings;
use strict;
our $VERSION = '0.1';

# Define minimum standard class metadata.

UR::Object::Type->define(
    class_name => 'UR::Object::LegacySet::DefinitionType::Parameterized',
    is => ['UR::Object::LegacySet'],
);

# Override the constructor to support defining the set members at creation time.

sub create {
    my $class = shift;
    my %params = @_;
    my $params = delete $params{params};
    my $template = delete $params{template};
    if ($params and $template) {
        die "Both params and initial_membership_source_set supplied to create()!"
    }
    my $self = $class->SUPER::create(%params);
    return unless $self;
    
    if ($params) {
        # preprocess the params to get complete metadata
        $params = $class->member_class_name->preprocess_params(%$params);
    }
    elsif ($template) {
        if ($template->isa(__PACKAGE__)) {
            # you have a twin sister...
            # get the params from the previous set
            $params = $template->{_params_all};
        }
        else {
            # safe, slow, ugly
            # make a parameter out of the other class's member ID list
            $params = $class->member_class_name->preprocess_params(
                id => [ $template->get_member_ids ],
            );
        }
    }
    else {
        $params = $class->member_class_name->preprocess_params();
    }
    
    # get the class of object which stores these parameters
    my $param_class = $class->meta_param_class_name;
    
    # process the parameters
    my @deleteme_on_failure = ($self);
    for my $key (keys %$params) {            
        my $value = $params->{$key};
        
        # preserve
        if ($key =~ /^_/) {
            $self->{_params_prop}{$key} = $value;
            $self->{_params_all}{$key} = $value;
        } 
        else {
            $self->{_params_meta}{$key} = $value;
            $self->{_params_all}{$key} = $value;
        }        
        
        # make an object
        my $op;
        if (ref($value) eq 'HASH') {
            $op = lc($value->{operator});
            $value = $value->{value};
        }
        elsif (ref($value) eq 'ARRAY') {
            $op = "";
            die "In clause not implemented!";
        }
        else {
            $op = "";
        }
        my $param = $param_class->create(
            set_id => $self->id,
            param_name => $key,
            operator => $op,
            value => $value
        );            
        unless ($param) {
            $class->error_message("Error creating parameters!");
            for (@deleteme_on_failure) {                
                $_->delete;
            }
            return;                
        }

    }
    
    return $self;
}

sub _params_prop_hashref {
    return $_[0]->{_params_prop}
}

sub _params_prop_list {
    return %{ $_[0]->{_params_prop} };
}

sub _params_meta_hashref {
    return $_[0]->{_params_meta}
}

sub _params_all_hashref {
    return $_[0]->{_params_all}
}

sub _matches {
    no warnings;
    my $self = shift;
    my $params = $self->{_params_prop_hashref};
    for my $key (keys %$params)
    {
        return 0 unless $self->$key eq $params->{$key}
    }
    return 1;
}

# The ID-based interface to the set is required.
# The object-based interface is inherited, as are the default operation methods.

sub has_member_id {
    my $self = shift;
    my $has_id = shift;
    my $set_id = $self->id;
    my $params = $self->_params_all_hashref;
    if (my $id = $params->{id}) {
        if (not ref($id)) {
            return ($id eq $has_id ? 1 : 0)
        }
        elsif (ref($id) eq 'ARRAY') {
            return (grep { $_ eq $has_id } @$id ? 1 : 0)
        }
        else {
            # We can't do multiple ID clauses with a logical and yet.
            # This might load all of the object's data to do the check.
            my $member_class_name = $self->member_class_name;
            my @params = $self->_params_prop_list;
            my @obj = $member_class_name->get(@params);
            return (grep { $_->id eq $has_id } @obj ? 1 : 0);
        }
    }
    else {
        # Add the ID to the list of params.
        my $member_class_name = $self->member_class_name;
        my @params = $self->_params_prop_list;
        my $obj = $member_class_name->get(@params, id => $has_id);
        return ($obj ? 1 : 0);
    }    
}

sub get_members {
    my $self = shift;        
    my $params = $self->_params_all_hashref;
    my $member_class_name = $self->member_class_name; 
    my @obj = $member_class_name->get($params);
    return @obj;
}

sub get_member_ids {
    my $self = shift;
    my @members = $self->get_members;
    return map { $_->id } @members;
}

sub add_member_ids {
}

sub remove_member_ids {
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
