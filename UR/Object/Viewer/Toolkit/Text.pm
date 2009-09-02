
=pod

=head1 NAME

UR::Object::Viewer::Toolkit::Text

=head1 SYNOPSIS

Methods called by UR::Object::Viewer to get toolkit specific support for
common tasks.

=cut

package UR::Object::Viewer::Toolkit::Text;

use warnings;
use strict;
require UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::Viewer::Toolkit',
    has => [
        toolkit_name    => { is_constant => 1, value => "text" },
        toolkit_module  => { is_constant => 1, value => "(none)" },  # is this used anywhere?
    ]
);

our $VERSION = '0.1';

sub show_viewer {
    my $class = shift;
    my $viewer = shift;
    my $widget = $viewer->get_widget;
    return $$widget;
}

# This doesn't really apply for text?!
sub hide_viewer {
return undef;

    my $class = shift;
    my $viewer = shift;
    my $widget = $viewer->get_widget;
    print "DEL: $widget\n";
    return 1;
}

# This doesn't really apply for text?!
sub create_window_for_viewer {
return undef;

    my $class = shift;
    my $viewer = shift;
    my $widget = $viewer->get_widget;
    print "WIN: $widget\n";
    return 1;
}

# This doesn't really apply for text?!
sub delete_window_around_viewer {
return undef;

    my $class = shift;
    my $widget = shift; 
    print "DEL: $widget\n";
    return 1;
}

1;
