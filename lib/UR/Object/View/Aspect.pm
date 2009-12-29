package UR::Object::View::Aspect;

use warnings;
use strict;
require UR;

our $VERSION = $UR::VERSION;;

class UR::Object::View::Aspect {
    id_by => [
        parent_view     => { is => 'UR::Object::View', id_by => 'parent_view_id', 
                            doc => "the id of the viewer object this is an aspect-of" },
        
        number          => { is => 'Integer', 
                            doc => "aspects of a view are numbered" },
    ],
    has => [
        name            => { is => 'Text', 
                            is_mutable => 0, 
                            doc => 'the name of the property/method on the subject which returns the value to be viewed' },
    ],
    has_optional => [
        label           => { is => 'Text', 
                            doc => 'display name for this aspect' },
        
        position        => { is => 'Scalar', 
                            doc => 'position of this aspect within the parent view (meaning is view and toolkit dependent)' },

        delegate_view      => { is => 'UR::Object::View', id_by => 'delegate_view_id', 
                            doc => "This aspect gets rendered via another viewer" },
    ],
};

sub create {
    my $class = shift;
    my $bx = $class->define_boolexpr(@_);

    # TODO: it would be nice to have this in the class definition:
    #  increment_for => 'parent_view'
    unless ($bx->value_for('number')) {
        if (my $parent_view_id = $bx->value_for('parent_view_id')) {
            my $parent_view = UR::Object::View->get($parent_view_id);
            my @previous_aspects = $parent_view->aspects;
            $bx = $bx->add_filter(number => scalar(@previous_aspects)+1);
        }
    }
    unless ($bx->value_for('label')) {
        if (my $label = $bx->value_for('name')) {
            $label =~ s/_/ /g;
            $bx = $bx->add_filter(label => $label);
        }
    }

    my $self = $class->SUPER::create($bx);
    return unless $self;

    my $name = $self->name;
    unless ($name) {
        $self->error_message("No name specified for aspect!");
        $self->delete;
        return;
    }

    return $self; 
}

sub _create_delegate_view {
    my $self = shift;
    my $parent_view = $self->parent_view;
    my $name = $self->name;
    my $subject_class_name = $parent_view->subject_class_name;
    my $property_meta = $subject_class_name->__meta__->property($name);
    if ($property_meta) {
        my $aspect_type = $property_meta->data_type;
        if ($aspect_type->can("__meta__")) {
            my $delegate_view = $aspect_type->create_view(
                subject_class_name => $aspect_type,
                perspective => $parent_view->perspective,
                toolkit => $parent_view->toolkit,
            );
            $delegate_view ||= $aspect_type->create_view(
                subject_class_name => $aspect_type,
                toolkit => $parent_view->toolkit,
            );
            unless ($delegate_view) {
                $self->error_message("Error creating delegate view for $name ($aspect_type)!");
                $self->delete;
                return;
            }
            $self->delegate_view($delegate_view);
        }
    }
    else {
        unless ($subject_class_name->can($name)) {
            $self->error_message("No property/method $name found on $subject_class_name!  Invalid aspect!");
            $self->delete;
            return;
        }
    }
}

1;

=pod

=head1 NAME

UR::Object::View::Aspect - a specification for one aspect of a view 

=head1 SYNOPSIS

 my $v = $o->create_view(
   perspective => 'default',
   toolkit => 'xml',
   aspects => [
     'id',
     'name',
     'title',
     { 
        name => 'department', 
        perspective => 'logo'
     },
     { 
        name => 'boss',
        label => 'Supervisor',
        aspects => [
            'name',
            'title',
            { 
              name => 'subordinates',
              perspective => 'graph by title'
            }
        ]
     }
   ]
 );

=cut


