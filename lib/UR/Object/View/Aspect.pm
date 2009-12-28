
package UR::Object::View::Aspect;

use warnings;
use strict;

our $VERSION = $UR::VERSION;;

require UR;

class UR::Object::View::Aspect {
    id_by => [
        viewer      => { is => 'UR::Object::View', id_by => 'viewer_id', doc => "ID of the viewer object this is an aspect-of" },
        position    => { is => 'Integer', doc => "The order to appear in the viewer" },
    ],
    has => [
        aspect_name => { is => 'String', doc => 'display name for this aspect' },
    ],
    has_optional => [
        delegate_viewer     => { is => 'UR::Object::View', id_by => 'delegate_viewer_id', doc => "This aspect gets rendered via another viewer" },
        method              => { is => 'String', doc => 'Name of the method in the subject class to retrieve the data to be displayed' },
    ],
} 

sub name {
    shift->aspect_name;
}

sub title {
    shift->name;
}

1;

=pod

=head1 NAME

UR::Object::View::Aspect - a base class for a viewer which renders a particular aspect of its subject

=cut


