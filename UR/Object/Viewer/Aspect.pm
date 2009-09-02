
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
    has => [qw/
        viewer_id 
        aspect_name
        position         
        delegate_viewer_id
    /],
    id_properties => [qw/viewer_id position/],
) 
or die ("Failed to make class metadata for " . __PACKAGE__);

sub name {
    shift->aspect_name;
}

sub title {
    shift->name;
}

sub method {
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
