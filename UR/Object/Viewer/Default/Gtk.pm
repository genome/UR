package UR::Object::Viewer::Default::Gtk;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::Viewer',
);

sub _create_widget {
    my $self = shift;
    my $label = Gtk::Label->new("<new>");
    return $label;
}

sub _update_widget_from_subject {
    my $self = shift;
    my @changes = @_;  # this is not currently resolved and passed-in
    
    my $subject = $self->get_subject();
    my @aspects = $self->get_aspects;
    my $widget = $self->get_widget();
    
    my $text = $self->subject_class_name;
    $text .= " with id " . $subject->id . "\n" if $subject;
    for my $aspect (sort { $a->position <=> $b->position } @aspects) {       
        my $aspect_name = $aspect->aspect_name;
        $text .= "\n" . $aspect_name . ": ";
        if ($subject) {
            my @value = $subject->$aspect_name;
            $text .= join(", ", @value);
        }
        else {
            $text .= "-";
        }
    }
    $widget->set_text($text);
    return 1;
}

sub _update_subject_from_widget {
    Carp::confess("This widget shouldn't be able to write to the object, it's a label?  How did I get called?");
}

sub _add_aspect {
    shift->_update_widget_from_subject;
}

sub _remove_aspect {
    shift->_update_widget_from_subject;
}

1;

