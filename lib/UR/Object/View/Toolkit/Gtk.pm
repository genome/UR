package UR::Object::View::Toolkit::Gtk;

use warnings;
use strict;

our $VERSION = $UR::VERSION;;

require UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::View::Toolkit',
    has => [
        toolkit_name    => { is_constant => 1, value => "gtk" },
        toolkit_module  => { is_constant => 1, value => "Gtk" },
    ]
);

sub show_view_modally {
    my $class = shift;
    my $view = shift;
    my $window = $class->create_window_for_view($view);
    return unless $window;
    $window->set_modal(1);
    $window->show_all;
    $window->signal_connect("destroy", sub { Gtk->main_quit });
    Gtk->main;
    return 1;
}

sub show_view {
    my $class = shift;
    my $view = shift;
    my $window = $class->create_window_for_view($view) or return;
    $window->show_all;
    return 1;
}

sub hide_view {
    my $class = shift;
    my $view = shift;
    $class->delete_window_around_view($view) or return;
    my $widget = $view->widget;
    $widget->hide();
    return 1;
}

our %open_editors;
sub create_window_for_view {
    my $class = shift;
    my $view = shift;
    
    my @params = @_;
    my %params = @_; #_compile_hash(@_);
    
    # Make a window for the view.
    my $win = new Gtk::Window;
    $win->set_title("test title");
    
    # Extract the widget underlying the view and put it in the window.
    my $widget = $view->widget;
    Carp::confess($widget) unless($widget);
    $win->add($widget);
    
    # Put the window in the hash of editors.
    my $subject = $view->subject();
    $open_editors{$view} = $win;
    
    # Show the editor.        
    $win->set_default_size(400,200);
    $win->show_all;

    # Destroy view if window is cloased.
    $win->signal_connect('delete_event', sub 
    {       
        if (App::UI->remove_window($win))
        {
            $class->delete_window_around_view($view);
            return 0;
        }
        else
        {
            return 1;
        }
    });
    
    # Add to the list of windows.
    App::UI::Gtk->add_window($win);
    
    # Return this.
    return $win;
}

sub delete_window_around_view {
    my $class = shift;
    my $view = shift;
    my $subject = $view->subject;
    my $widget = $view->widget;
    my $win = delete $open_editors{$view};
    $win->remove($widget);
    $win->destroy;
    App::UI::Gtk->remove_window($win);
    return 1;
}

1;


=pod

=head1 NAME

UR::Object::View::Toolkit::Gtk - Declaration of Gtk as a View toolkit type

=head1 SYNOPSIS

Methods called by UR::Object::View to get toolkit specific support for
common tasks.

=cut


