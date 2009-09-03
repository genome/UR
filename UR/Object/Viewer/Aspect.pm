
=pod

=head1 NAME

UR::Object::Viewer::Aspect - a base class for a viewer which renders a particular aspect of its subject

=head1 SYNOPSIS
    
    $v = $obj->create_viewer(
        visible_aspects => [qw/some_property some_method/], 
    );
    $v->show_modal();
  
    $v->set_subject($another_obj_same_class);
    $v->show();
    App::UI->event_loop();
  
=cut


package UR::Object::Viewer::Aspect;

use warnings;
use strict;

our $VERSION = '0.1';

require UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    has => [
        viewer_id   => { is => 'SCALAR', doc =>"ID of the Viewer object this is an aspect of" },
        viewer      => { is => 'UR::Object::Viewer', id_by => 'viewer_id' },
        aspect_name => { is => 'String', doc => 'display name for this aspect' },
        method      => { is => 'String', doc => 'Name of the method in the subject class to retrieve the data to be displayed' },
        position    => { is => 'Integer', doc => "The order to appear in the viewer" },
    ],
    has_optional => [
        delegate_viewer_id => { is => 'SCALAR', doc => "This aspect gets rendered via another viewer" },
        delegate_viewer    => { is => 'UR::Object::Viewer', id_by => 'delegate_viewer_id' },
    ],
    id_properties => [qw/viewer_id position/],
) 
or die ("Failed to make class metadata for " . __PACKAGE__);

sub name {
    shift->aspect_name;
}

sub title {
    shift->name;
}

1;

# Object viewer aspects.
# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

#$Id$
