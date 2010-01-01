package UR::Object::View::Default::Xml;

use strict;
use warnings;
use IO::File;

class UR::Object::View::Default::Xml {
    is => 'UR::Object::View::Default::Text',
    has_constant => [
        toolkit     => { value => 'xml' },
    ]
};

sub _generate_content {
    my $self = shift;

    my $subject = $self->subject();
    return '' unless $subject;

    # the header line is the class followed by the id
    my $text = '<' . $self->subject_class_name;
    my $subject_id_txt = $subject->id;
    $subject_id_txt = "'$subject_id_txt'" if $subject_id_txt =~ /\s/;
    $text .= " id=$subject_id_txt>\n";
    
    # the content for any given aspect is handled separately
    my @aspects = $self->aspects;
    for my $aspect (sort { $a->number <=> $b->number } @aspects) {
        next if $aspect->name eq 'id';
        my $aspect_text = $self->_generate_content_for_aspect($aspect);
        $text .= $aspect_text;
    }

    $text .= '</' . $self->subject_class_name . ">\n";

    return $text;
}

sub _generate_content_for_aspect {
    # This does two odd things:
    # 1. It gets the value(s) for an aspect, then expects to just print them
    #    unless there is a delegate viewer.  In which case, it replaces them 
    #    with the delegate's content.
    # 2. In cases where more than one value is returned, it recycles the same
    #    viewer and keeps the content.
    # 
    # These shortcuts make it hard to abstract out logic from toolkit-specifics

    my $self = shift;
    my $aspect = shift;
    my @value = @_;

    my $subject = $self->subject;  
    my $aspect_name = $aspect->name;
    my $indent_text = $self->indent_text;
    
    my $aspect_meta = $self->subject_class_name->__meta__->property($aspect_name);
    my $label = ($aspect_meta ? $aspect_meta->singular_name : $aspect_name);

    my @value = $subject->$aspect_name;
    if (@value == 1 and ref($value[0]) eq 'ARRAY') {
        @value = @{$value[0]};
    }

    if (@value == 0) {
        return ''; 
    }
        
    if (Scalar::Util::blessed($value[0])) {
        unless ($aspect->delegate_view) {
            $aspect->generate_delegate_view;
        }
    }
    
    # Delegate to a subordinate viewer if needed.
    # This means we replace the value(s) with their
    # subordinate widget content.
    my $aspect_text = '';
    if (my $delegate_view = $aspect->delegate_view) {
        foreach my $value ( @value ) {
            $delegate_view->subject($value);
            $delegate_view->_update_view_from_subject();
            $value = $delegate_view->content();
            $value =~ s|^\<(\S+)|\<$label type=$1|;
            $value =~ s|</(\S+)\>$|</$label>|;
            $value = $self->_indent($indent_text,$value);
            $aspect_text .= $value;
        }
    }
    else {
        $aspect_text .= $indent_text . "<$label>";
        if (@value < 2) {
            if ($value[0] !~ /\n/) {
                # single value, no newline
                $aspect_text .= $value[0];
            }
            else {
                # single value with newlines
                $aspect_text .= 
                    "\n" 
                    . $self->_indent($indent_text . $indent_text, $value[0]) 
            }
        }
        else {
            $aspect_text .= "\n";
            for my $value (@value) {
                if ($value !~ /\n/) {
                    # multi-value no newline(s)
                    $aspect_text .= $indent_text . "<$aspect_name>$value</$aspect_name>\n";
                }
                else {
                    # multi-value with newline(s)
                    $aspect_text .= $self->_indent($indent_text . $indent_text, $value) 
                }
            }
            $aspect_text .= $indent_text;
        }
        $aspect_text .= "</$label>\n";
    }



    return $aspect_text;
}

sub _indent {
    my ($self,$indent,$value) = @_;
    chomp $value;
    my @rows = split(/\n/,$value);
    my $value_indented = join("\n", map { $indent . $_ } @rows);
    chomp $value_indented;
    return $value_indented . "\n";
}

1;


=pod

=head1 NAME

UR::Object::View::Default::Xml - represent object state in XML format 

=head1 SYNOPSIS

  $o = Acme::Product->get(1234);

  $v = $o->create_view(
      toolkit => 'xml',
      aspects => [
        'id',
        'name',
        'qty_on_hand',
        'outstanding_orders' => [   
          'id',
          'status',
          'customer' => [
            'id',
            'name',
          ]
        ],
      ],
  );

  $xml1 = $v->content;

  $o->qty_on_hand(200);
  
  $xml2 = $v->content;

=head1 DESCRIPTION

This class implements basic XML views of objects.  It has standard behavior for all text views.

=head1 SEE ALSO

UR::Object::View::Default::Text, UR::Object::View, UR::Object::View::Toolkit::XML, UR::Object::View::Toolkit::Text, UR::Object

=cut

