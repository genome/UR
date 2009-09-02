
=pod

=head1 NAME

UR::Object::Viewer - a base class for viewer/editors of UR::Object

=head1 SYNOPSIS

    $object = Acme::Rocket->get($some_id);
    
    $viewer = $object->create_viewer(
        perspective => "flight path"    # optional, default is "default"
        aspects => \@these_properties,  # optional, default is set in perspective
        toolkit => "gtk"                # optional, default is set by App::UI
    );
    
    $view->show_modal();
    
    
    $object2 = Acme::Rocket->get($another_id);    
    
    $viewer->set_subject($object2);
    $viewer->show_modal();    
    
    $viewer->show();
    App::UI->event_loop();

    $viewer = $object->create_viewer(
        perspective => "flight path"    # optional, default is "default"
        aspects => [
            'property1',
            'parts' => {  
                perspective => "ordered list",
                aspects => [qw/make model mileage/],
            },
            'property3',
        ]
        toolkit => "gtk"                # optional, default is set by App::UI
    );


=cut

package UR::Object::Viewer;

use warnings;
use strict;

our $VERSION = '0.1';

require UR;

UR::Object::Type->define(
    class_name => 'UR::Object::Viewer',
    id_properties => ['viewer_id'],
    properties => [
        viewer_id               => { },
        subject_class_name      => { is_abstract => 1, is_class_wide => 1, is_constant => 1, is_optional => 0 },   
        perspective             => { is_abstract => 1, is_class_wide => 1, is_constant => 1, is_optional => 0 },   
        toolkit                 => { is_abstract => 1, is_class_wide => 1, is_constant => 1, is_optional => 0 },
        subject_id              => { },    
        _subject_object         => { is_transient => 1, default_value => undef },        
        _widget                 => { is_transient => 1, default_value => undef },
    ],
);

# This writes non-property based accessors for some internal things.

our %default_values = 
(
    _next_aspect_position => 0,
    _misc_container => undef,    
);

UR::Util->generate_readwrite_methods(%default_values)
    or die "Failed to generate rw accessors for " . __PACKAGE__;


=pod

=head1 View Interface

=over 4

=item create

The constructor requires the following params to be specified as key-value pairs:

=over 4

=item subject_class_name
    
The class of subject this viewer will view.  Constant for any given viewer,
but this may be any abstract class up-to UR::Object itself.
    
=item perspective

Used to describe the layout engine which gives logical content
to the viewer.

=item toolkit

The specific (typically graphical) toolkit used to construct the UI.
Examples are Gtk, Gkt2, Qt, Tk, HTML, Curses.

=back

=item delete

The destructor deletes subordinate components, and the related widget, 
removing them all from the view of the user.

=item show

For stand-alone viewers, this puts the viewer in its own window.  For 
viewers which are part of a larger viewer, this makes the viewer widget
visible in the parent.

=item hide

Makes the viewer invisible.  This means hiding the window, or hiding the viewer
widget in the parent widget for subordinate viewers.

=item show_modal 

This method shows the viewer in a window, and only returns after the window is closed.
It should only be used for viewers which are a full interface capable of closing itself when done.

=item get_visible_aspects / add_visible_aspect / remove_visible_aspect

An "aspect" is some characteristic of the "subject" which is rendered in the 
viewer.  Properties of an aspect specifyable in the above methods are:

=over 4

=item method

The name of the method on the subject which returns the data to be rendered.

=item position

The position within the viewer of this aspect.  The actual meaning will
depend on the logic behind the perspective.

=item perspective

If a subordinate viewer will be used to render this aspect, this perspective
will be used to for that viewer.

=back

=cut

sub generate_support_class {
    my $self = shift;
    my $subject_class_name_plus_keyword = ref($self) || $self;
    my $extension_for_support_class = shift;
    
    return unless defined($extension_for_support_class);
    return unless $extension_for_support_class =~ /::/;
    
    my ($subject_class_name) = ($subject_class_name_plus_keyword =~ /^(.*)::Viewer$/);
    
    my $parent_class_name;
    for my $subject_parent_class_name ($subject_class_name->inheritance, "UR::Object") {
        
        my $possible_parent_class_name = 
            $subject_parent_class_name
            . "::Viewer::"
            . $extension_for_support_class;
        
        eval "use $possible_parent_class_name";
        # Ignore errors like "Can't locate <pathname> in @INC.  Others are probably
        # real errors like syntax problems
        if ($@ && $@ !~ m/^Can't locate /) {
            $self->error_message("Error while loading $possible_parent_class_name: $@");
            return;
        }

        my $possible_parent_class_meta = UR::Object::Type->is_loaded(
            class_name => $possible_parent_class_name
        );
        if ($possible_parent_class_meta) {        
            $parent_class_name = $possible_parent_class_name;
            last;
        }
    }
    return unless $parent_class_name;
    
    my $class_obj = UR::Object::Type->define(
        class_name => $subject_class_name . "::Viewer::" . $extension_for_support_class,
        is => [$parent_class_name],
    );
    $self->error_message(UR::Object::Type->error_message) unless $class_obj;
    return $class_obj;
}

sub create_viewer {
    my $class = shift;    

    if ($class ne __PACKAGE__) {
        # This is part of a $subclass->SUPER::create() call.  There's
        # nothing to do here except pass the call up the inheritance chain
        return $class->SUPER::create(@_);
    }
    
    # Otherwise, we're using this as a factory to create the correct viewer subclass 

    my %params = @_;
    
    my $subject_class_name = delete $params{subject_class_name};
    my $perspective = delete $params{perspective};
    my $toolkit = delete $params{toolkit};
    my $aspects = delete $params{aspects};
    
    $perspective = lc($perspective);
    $toolkit = lc($toolkit);
    
    if (%params) {
        my @params = %params;
        $class->error_message("Bad params: @params");
        return;
    }

    my $subclass_name = join("::",
        $subject_class_name,
        "Viewer",
        join ("",
            App::Vocabulary->filter_vocabulary (
                map { ucfirst(lc($_)) }
                split(/\s+/,$perspective)
            )
        ),
        join ("",
            App::Vocabulary->filter_vocabulary (
                map { ucfirst(lc($_)) }
                split(/\s+/,$toolkit)
            )
        )
      );
   
    my $subclass_meta = UR::Object::Type->get(class_name => $subclass_name);
    unless ($subclass_meta) {
        $class->error_message("Failed to find class $subclass_name!  Cannot create viewer!");
        Carp::confess();
    }
    
    unless($subclass_name->isa($class)) {
        die "Subclass $subclass_name does not inherit from $class?!";
    }
    
    my $self = $subclass_name->create(
        subject_class_name => $subject_class_name,
        perspective => $perspective,
        toolkit => $toolkit
    );
    return unless $self;

    if ($aspects) {
        my $position = 1;
        while (my $aspect_name = shift @$aspects) {
            my @aspect_params;
            if (ref($aspects->[0])) {
                @aspect_params = %{$aspects->[0]};
                shift @$aspects;
            }
            unless (
                $self->add_aspect(
                    aspect_name => $aspect_name,
                    position => $position,                    
                    @aspect_params,
                )
            ) {
                print "failed!\n";
                $self->remove_aspect();
                $self->delete;
                return;
            }
            $position++;
        }
    }
    
    return $self;
}

sub delete_object {
    # This covers the needs of both unload() and delete().
    # Ensure that we clean up after deletion of any kind.
    my $self = shift;
    foreach my $subscription ($self->_subscriptions)
    {
        my ($class, $id, $callback) = @$subscription;
        $class->cancel_change_subscription($id, $callback);
    }    
    return $self->SUPER::delete_object(@_);
}

sub show_modal {
    my $self = shift;
    $self->_toolkit_class->show_viewer_modally($self);
}

sub show {
    my $self = shift;
    $self->_toolkit_class->show_viewer($self);
}

sub hide {
    my $self = shift;
    $self->_toolkit_class->hide_viewer($self);
}

sub get_aspects {
    my $self = shift;
    return UR::Object::Viewer::Aspect->get(viewer_id => $self->id, @_);
}

sub add_aspect {
    my $self = shift;    
    my @previous_aspects = $self->get_aspects();
    my @creation_params;
    if (@_ == 1) {
        @creation_params = (aspect_name => shift(@_), position => scalar(@previous_aspects)+1);
    } 
    else {
        @creation_params = (position => scalar(@previous_aspects)+1, @_);
    }
    my $aspect = UR::Object::Viewer::Aspect->create(viewer_id => $self->id, @creation_params);
    if ($aspect and $self->_add_aspect($aspect)) {
        return 1;
    }
    else {
        $aspect->delete;
        Carp::confess("Failed to add aspect @_!"); 
    }
}

sub remove_aspect {
    my $self = shift;
    my @aspect_params;
    if (@_ == 1) {
        @aspect_params = (aspect_name => shift(@_));
    } 
    else {
        @aspect_params = @_;
    }    
    my @rm = UR::Object::Viewer::Aspect->get(viewer_id => $self->id, @aspect_params);
    for my $aspect (@rm) {
        my $aspect_name = $aspect->aspect_name; 
        $aspect->delete;
        unless ($self->_remove_aspect($aspect_name)) {
            die "Error removing aspect $aspect_name!";
        }
    }
    return 1;
}

=back

=head1 Subject Interface

=over 4

=item subject_class_name

This is constant for a given viewer.  Any assigned subject must be of this 
class directly or indirectly.

=item subject_id

This indicates WHICH object of the class C<subject_class_name> is visible.
This value can be changed directly, or indirecly by calling set_subject().

=item get_subject

Returns a reference to the current "subject" object.

=item set_subject

Sets the specified object to be the "subject" of the viewer.

=back

=cut

no warnings;
*subject_id = sub 
{
    if (@_ > 1)
    {
        my $self = $_[0];
        my $new_id = $_[1];
        my $old_id = $self->{subject_id};
        if ($old_id ne $new_id)
        {
            $self->{subject_id} = $new_id;
            $self->_bind_subject;
        }
    }
    return $_[0]->{subject_id};
};
use warnings;

sub get_subject
{
    my $self = shift;    
    if (my $obj = $self->{subject})
    {
        return $obj
    }    
    else
    {
        my $subject_id = $self->subject_id;
        return if not defined $subject_id;
        
        return $self->subject_class_name->get($self->subject_id);
    }
}


sub set_subject
{
    my $self = shift;    
    if (@_)
    {
        my $new_id = $_[0]->id;
        $DB::single = 1;
        $self->subject_id($new_id);
        my $expected_obj = $self->subject_class_name->get($self->subject_id);
        $self->{subject} = $_[0] unless $expected_obj eq $_[0];
        $self->_bind_subject;
    }
    if (my $obj = $self->{subject})
    {
        return $obj
    }
    else
    {
        $self->subject_class_name->get($self->subject_id);
    }
}


=pod

=head1 Toolkit Interface

=over 4

=item toolkit

A class method indicating what toolkit is used to render the view.
Possible values are Gtk, and hopefully Gtk2, Tk, Qt, HTML, Curses, etc.

=item get_widget

Returns the "widget" which is the rendered view.  The actual object
type depends on the toolkit named above.

=item _toolkit_class

Returns the name of a class which is derived from UR::Object::Toolkit
which implements certain utility methods for viewers of a given toolkit.

=back

=cut

sub get_widget {
    my $self = shift;
    my $widget = $self->{widget};
    unless ($widget) {
        $widget = $self->_create_widget;
        $self->{widget} = $widget;
    }
    return $widget
}

sub _toolkit_class
{
    my $self = shift;
    my $toolkit = $self->toolkit;
    return "UR::Object::Viewer::Toolkit::" . ucfirst(lc($toolkit));
}


=pod

=head1 Perspective Interface

When writing a new viewer, these methods should be implemented to 
handle the tasks described.  The class can be named anything, though
the recommended naming structure for a viewer is something like:

     Acme::Rocket::Viewer::FlightPath::Gtk2
     \          /           \    /      \
     subject class        perspective    toolkit
      
A module like ::FlightPath::Gtk2 might keep most logic in
Acme::Rocket::Viewer::FlightPath, and only toolkit specifics in
Gtk2, but this is not required as long as the module functions.

=over 4

=item _create_widget

This should be implemented in a given perspective/toolkit module to actually
create the GUI using the appropriate toolkit.  It will be called before the
specific subject is known, so all widget creation which is subject-specific 
should be done in _bind_subject().

=item _bind_subject

This method has a default implementation which does a general subscription
to changes on the subject.  It propbably does not need to be overridden
in custom viewers.

This does additional changes to the widget when a subject is set, unset, or 
switched.  Implementations should take an undef subject, and also expect
to un-bind a previously existing subject if there is one set. 

=item _update_widget_from_subject

If when the subject changes this method will be called on all viewers
which render the changed aspect of the subject.

=item _update_subject_from_widget

When the widget changes, it should call this method to save the GUI changes
to the subject.

=back

=cut

sub _create_widget
{
    Carp::confess("The _create_widget method must be implemented for all concrete "
        . " viewer subclasses.  No _create_widget for " 
        . (ref($_[0]) ? ref($_[0]) : $_[0]) . "!");
}

sub _bind_subject 
{
    my $self = shift;
    my $subject = $self->get_subject();
    my $subscriptions = $self->{subscriptions};

    # See uf we;ve already done this.    
    return 1 if $subscriptions->{$subject};

    # Wipe subscriptions from the last bound subscription(s).
    for (keys %$subscriptions) {
        my $s = delete $subscriptions->{$_};
        $subject->cancel_change_subscription(@$s);
    }

    # Make a new subscription for this subject
    my $subscription = $subject->create_subscription(
        callback => sub {
            $self->_update_widget_from_subject(@_);
        }
    );
    $self->{subscriptions}{$subject} = $subscription;
    
    # Set the viewer to show initial data.
    $self->_update_widget_from_subject;
    
    return 1;
}

sub _update_widget_from_subject
{
    Carp::confess("The _update_widget_from_subject method must be implemented for all concreate "
        . " viewer subclasses.  No _update_subject_from_widgetfor " 
        . (ref($_[0]) ? ref($_[0]) : $_[0]) . "!");
}

sub _update_subject_from_widget
{
    Carp::confess("The _update_widget_from_subject method must be implemented for all concreate "
        . " viewer subclasses.  No _update_subject_from_widgetfor " 
        . (ref($_[0]) ? ref($_[0]) : $_[0]) . "!");
}

1;

# Object viewers.
# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

#$Id: /mirror/perl_modules/branches/ur-convert4/UR/Object/Viewer.pm 1103 2006-10-13T23:56:32.111234Z ssmith  $
