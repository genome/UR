package UR::Object::View::Default::Text;

use strict;
use warnings;

class UR::Object::View::Default::Text {
    is => 'UR::Object::View',
    has_constant => [
        perspective => { value => 'default' },
        toolkit     => { value => 'text' },
    ],
    has => [
        indent_text => { is => 'Text', default_value => '  ', doc => 'indent child views with this text' },
    ],
};

sub _create_widget {
    # The "widget" for a text view is a pair of items:
    # The first is a scalar reference to hold the content.
    # The second is an I/O handle to which it will display.

    # Note that the former could be something tied to an object, 
    # a file, or other external storage, though it is 
    # simple by default.
    
    # The later is STDOUT unless overridden/changed.
    my $self = shift;
    my $scalar_ref = '';
    my $fh = 'STDOUT';
    return [\$scalar_ref,$fh];
}

# special to text views
sub content {
    # retuns the current value of the scalar ref containing the text content.
    my $self = shift;
    my $widget = $self->widget();
    my ($content_ref,$output_stream) = @$widget;
    return $$content_ref;
}

# special to text views
sub output_stream {
    # retuns the current value of the handle to which we render.
    my $self = shift;
    my $widget = $self->widget();
    my ($content_ref,$output_stream) = @$widget;
    return $$content_ref;
}

sub show {
    # Showing a text view typically prints to STDOUT
    my $self = shift;
    my $widget = $self->widget();
    my ($content_ref,$output_stream) = @$widget;
    $output_stream->print($$content_ref,"\n");
}

sub _update_subject_from_view {
    Carp::confess('currently text views are read-only!');
}

sub _update_widget_from_subject {
    my $self = shift;
    my $indent_text = $self->indent_text || '  ';

    my $text = $self->subject_class_name;
    
    my $subject = $self->subject();
    $text .= " with id " . $subject->id if $subject;
    $text .= "\n";

    my @aspects = $self->aspects;
    my $aspect_text;
    for my $aspect (sort { $a->number <=> $b->number } @aspects) {       
        $aspect_text = $indent_text . $aspect->label . ": ";
        
        if (!$subject) {
            $aspect_text .= "-\n";
            next;
        }
        
        my $aspect_name = $aspect->name;
        my @value = $subject->$aspect_name;
        
        if (@value == 0) {
            $aspect_text .= "-\n";
            next;
        }
        
        if (@value == 1 and ref($value[0]) eq 'ARRAY') {
            @value = @{$value[0]};
        }
        
        if (Scalar::Util::blessed($value[0])) {
            unless ($aspect->delegate_view) {
                $aspect->generate_delegate_view;
            }
        }
        
        # Delegate to a subordinate viewer if needed.
        # This means we replace the value(s) with their
        # subordinate widget content.
        if (my $delegate_view = $aspect->delegate_view) {
            if (@value == 1) {
                $delegate_view->subject($value[0]);
                $delegate_view->_update_widget_from_subject();
                $value[0] = $delegate_view->content();
            }
            else {
                # TODO: it is bad to recycle a view here??
                # Switch to a set view, which is the standard lister.
                foreach my $value ( @value ) {
                    $delegate_view->subject($value);
                    $delegate_view->_update_widget_from_subject();
                    $value = $delegate_view->content();
                }
            }
        }
        
        if (@value == 1 and index($value[0],"\n") == -1) {
            # one item, one row in the value or sub-view of the item:
            $aspect_text .= $value[0] . "\n";
        }
        else {
            my $aspect_indent;
            if (@value == 1) {
                # one level of indent for this sub-view's sub-aspects
                # zero added indent for the identity line b/c it's next-to the field label

                # aspect1: class with id ID
                #  sub-aspect1: value1
                #  sub-aspect2: value2
                $aspect_indent = $indent_text;
            }
            else {
                # two levels of indent for this sub-view's sub-aspects
                # just one level for each identity

                # aspect1: ... 
                #  class with id ID
                #   sub-aspect1: value1
                #   sub-aspect2: value2
                #  class with id ID
                #   sub-aspect1: value1
                #   sub-aspect2: value2
                $aspect_text .= "...\n";
                $aspect_indent = $indent_text . $indent_text;
            }

            for my $value (@value) {
                my @rows = split(/\n/,$value);
                my $value_indented = join("\n", map { $aspect_indent . $_ } @rows);
                chomp $value_indented;
                $aspect_text .= $value_indented . "\n";
            }
        }
    }
    continue {
        $text .= $aspect_text;
    }

    # The text widget won't print anything until show(),
    # so store the data in the content for now.
    my $widget = $self->widget();
    my ($content_ref,$fh) = @$widget;
    $$content_ref = $text;
    return 1;
}

1;


=pod

=head1 NAME

UR::Object::View::Default::Text - object views in text format

=head1 DESCRIPTION

This class provides code that implements a basic text renderer for UR objects.

=head1 SEE ALSO

UR::Object::View, UR::Object

=cut
