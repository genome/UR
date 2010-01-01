package UR::Object::View::Default::Xml;

use strict;
use warnings;
use IO::File;

class UR::Object::View::Default::Xml {
    is => 'UR::Object::View::Default::Text',
);


sub _create_widget {
    my $self = shift;
    my $fh = IO::File->new('>-');
    return $fh;
}

sub _update_widget_from_subject {
    my $self = shift;
    my @changes = @_;  # this is not currently resolved and passed-in
    
    my $subject = $self->subject();
    my @aspects = $self->aspects;
    
    my $text = $self->subject_class_name;
    $text .= " with id " . $subject->id if $subject;

    for my $aspect (sort { $a->position <=> $b->position } @aspects) {       
        my $aspect_text = '';
        my $label = $aspect->label;
        my $aspect_name = $aspect->name;
        $aspect_text .= "\t" . $label . ": ";
        if ($subject) {
            my @value = $subject->$aspect_name;
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
            no warnings 'uninitialized';
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
    my $fh = $self->widget;
    return unless $fh;

    $fh->print($self->buf,"\n");
}



1;


=pod

=head1 NAME

UR::Object::View::Default::Xml - Text adaptor for object viewers

=head1 DESCRIPTION

This class provides code that implements a basic text renderer for UR objects.

=head1 SEE ALSO

UR::Object::View, UR::Object

=cut
