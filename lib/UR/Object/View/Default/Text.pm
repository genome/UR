package UR::Object::View::Default::Text;

use strict;
use warnings;
use IO::File;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::View',
    has => [
        content     => { is => 'Text', is_optional => 1 },

    ],
);

sub show {
    my $self = shift;

    my $content = $self->content;
    print($$content,"\n");
}

sub widget {
    my $self = shift;
    return $self->content;
}

sub _create_widget {
    my $self = shift;
    $self->_set_content();
    $self->_widget(
}

sub _set_subject {
    my $self = shift;
    $self->_set_content();
}

sub _add_aspect {
    my $self = shift;
    $self->_set_content();
}

sub _remove_aspect {
    my $self = shift;
    $self->_set_content();
}

sub _update_view_from_subject {
    my $self = shift;
    $self->_set_content();
}

sub _update_subject_from_view {
    Carp::confess('currently text views are read-only!');
}

sub _set_content {
    my $self = shift;
    
    my $text = $self->subject_class_name;
    
    my $subject = $self->subject();
    $text .= " with id " . $subject->id if $subject;

    my @aspects = $self->aspects;
    for my $aspect (sort { $a->number <=> $b->number } @aspects) {       
        my $aspect_text = '';
        my $aspect_label = $aspect->label;
        my $aspect_method = $aspect->name;
        $aspect_text .= "  " . $aspect_label . ": ";
        if ($subject) {
            my @value = $subject->$aspect_method;
            if (@value == 1 and ref($value[0]) eq 'ARRAY') {
                @value = @{$value[0]};
            }
                
            # Delegate to a subordinate viewer if need be
            if ($aspect->delegate_view_id) {
                my $delegate_viewer = $aspect->delegate_view;
                foreach my $value ( @value ) {
                    $delegate_viewer->subject($value);
                    $delegate_viewer->_update_widget_from_subject();
                    $value = $delegate_viewer->content();
                }
            }
            no warnings 'uninitialized';
            $aspect_text .= join(", ", @value);
        }
        else {
            $aspect_text .= "-";
        }
        $text .= "\n$aspect_text";
        
    }
    # The text widget won't print anything until show(),
    # so store the data in the contentfer for now
    $self->content($text);
    return 1;
}




1;


=pod

=head1 NAME

UR::Object::View::Default::Text - Text adaptor for object viewers

=head1 DESCRIPTION

This class provides code that implements a basic text renderer for UR objects.

=head1 SEE ALSO

UR::Object::View, UR::Object

=cut
