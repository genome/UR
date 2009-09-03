package UR::Object::Viewer::Default::Text;

use strict;
use warnings;
use IO::File;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::Viewer',
    has_optional => [
        buf => { is => 'String' },
    ],
);


sub _create_widget {
    my $self = shift;
    my $fh = IO::File->new('>-');
    return $fh;
}

sub _update_widget_from_subject {
    my $self = shift;
    my @changes = @_;  # this is not currently resolved and passed-in
    
    my $subject = $self->get_subject();
    my @aspects = $self->get_aspects;
    
    my $text = $self->subject_class_name;
    $text .= " with id " . $subject->id if $subject;

    for my $aspect (sort { $a->position <=> $b->position } @aspects) {       
        my $aspect_text = '';
        my $aspect_name = $aspect->aspect_name;
        my $aspect_method = $aspect->method;
        $aspect_text .= "\t" . $aspect_name . ": ";
        if ($subject) {
            my @value = $subject->$aspect_method;
            if (@value == 1 and ref($value[0]) eq 'ARRAY') {
                @value = @{$value[0]};
            }
                
            # Delegate to a subordinate viewer if need be
            if ($aspect->delegate_viewer_id) {
                my $delegate_viewer = $aspect->delegate_viewer;
                foreach my $value ( @value ) {
                    $delegate_viewer->set_subject($value);
                    $delegate_viewer->_update_widget_from_subject();
                    $value = $delegate_viewer->buf();
                }
            }
            $aspect_text .= join(", ", @value);
        }
        else {
            $aspect_text .= "-";
        }
        $text .= "\n$aspect_text";
        
    }
    # The text widget won't print anything until show(),
    # so store the data in the buffer for now
    $self->buf($text);
    return 1;
}

sub _update_subject_from_widget {
    1;
}

sub _add_aspect {
    1;
}

sub _remove_aspect {
    1;
}

sub show {
    my $self = shift;
    my $fh = $self->get_widget;
    return unless $fh;

    $fh->print($self->buf,"\n");
}



1;

