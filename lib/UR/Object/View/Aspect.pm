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
                            doc => 'the name of the property/method on the subject which returns the value to be viewed' },
        
    ],
    has_optional => [
        label           => { is => 'Text', 
                            doc => 'display name for this aspect' },
        
        position        => { is => 'Scalar', 
                            doc => 'position of this aspect within the parent view (meaning is view and toolkit dependent)' },

        delegate_view   => { is => 'UR::Object::View', id_by => 'delegate_viewer_id', 
                            doc => "This aspect gets rendered via another viewer" },

    ],
};

sub create {
    my $class = shift;

    # TODO: it would be nice to have this in the class definition:
    #  increment_for => 'parent_view'

    my $bx = $class->define_boolexpr(@_);
    unless ($bx->value_for('number')) {
        if (my $parent_view_id = $bx->value_for('parent_view_id')) {
            my @a = UR::Object::View->get($parent_view_id);
            $bx = $bx->add_filter(number => scalar(@a)+1);
        }
    }
    $class->SUPER::create($bx);
}

1;

=pod

=head1 NAME

UR::Object::View::Aspect - a base class for a viewer which renders a particular aspect of its subject

=cut


