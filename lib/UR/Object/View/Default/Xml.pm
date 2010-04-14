package UR::Object::View::Default::Xml;

use strict;
use warnings;
use IO::File;
use XML::Dumper;

class UR::Object::View::Default::Xml {
    is => 'UR::Object::View::Default::Text',
    has_constant => [
        toolkit     => { value => 'xml' },
    ]
};

sub xsl_template_files {
    my $self = shift;  #usually this is a view without a subject attached
    my $output_format = shift;
    my $root_path = shift;
    my $perspective = shift || lc($self->perspective);

    my @xsl_names = map {
       $_ =~ s/::/_/g;
       my $pf = "/$output_format/$perspective/" . lc($_) . '.xsl';
       my $df = "/$output_format/default/" . lc($_) . '.xsl';

       -e $root_path . $pf ? $pf : (-e $root_path . $df ? $df : undef)
    } $self->all_subject_classes_ancestry;

    my @found_xsl_names = grep { 
        defined
    } @xsl_names;

    return @found_xsl_names;
}

sub _generate_content {
    my $self = shift;

    my $subject = $self->subject();
    return '' unless $subject;

    # the header line is the class followed by the id
    my $text = '<object type="' . $self->subject_class_name . '"';
    my $subject_id_txt = $subject->id;
    $subject_id_txt =~ s/\t/%09/g;
    $text .= " id=\"$subject_id_txt\">\n";
    $text .= "  <display_name>" . $subject->__display_name__ . "</display_name>\n"; 
    $text .= "  <label_name>" . $subject->__label_name__ . "</label_name>\n";

    $text .= "  <types>\n";
    foreach my $c ($self->subject_class_name,$subject->__meta__->ancestry_class_names) {
        $text .= "    <isa type=\"$c\"/>\n";
    }
    $text .= "  </types>\n";
   
    unless ($self->_subject_is_used_in_an_encompassing_view()) {
        # the content for any given aspect is handled separately
        my @aspects = $self->aspects;
        if (@aspects) {
            for my $aspect (sort { $a->number <=> $b->number } @aspects) {
                next if $aspect->name eq 'id';
                my $aspect_text = $self->_generate_content_for_aspect($aspect);
                $text .= $aspect_text;
            }
        }
    }
    $text .= "</object>\n";

    return $text;
}

sub _generate_content_for_aspect {
    # This does two odd things:
    # 1. It gets the value(s) for an aspect, then expects to just print them
    #    unless there is a delegate view.  In which case, it replaces them 
    #    with the delegate's content.
    # 2. In cases where more than one value is returned, it recycles the same
    #    view and keeps the content.
    # 
    # These shortcuts make it hard to abstract out logic from toolkit-specifics

    my $self = shift;
    my $aspect = shift;

    my $subject = $self->subject;  
    my $aspect_name = $aspect->name;
    my $indent_text = $self->indent_text;
    
    my $aspect_meta = $self->subject_class_name->__meta__->property($aspect_name);

    my @value;
    eval {
        @value = $subject->$aspect_name;
#        if (@value == 1 and ref($value[0]) eq 'ARRAY') {
#            @value = @{$value[0]};
#        }
    };
    if ($@) {
#        @value = ('(exception)');

        my ($file,$line) = ($@ =~ /at (.*?) line (\d+)$/m);

        my $aspect_text = '';

        $aspect_text .= $indent_text . "<aspect name=\"$aspect_name\">\n";
        $aspect_text .= $indent_text . $indent_text . "<exception file=\"$file\" line=\"$line\"><![CDATA[$@]]></exception>\n";
        $aspect_text .= $indent_text . "</aspect>\n";
        return $aspect_text;
    }
    
    if (@value == 0) {
        return ''; 
    }
        
    if (Scalar::Util::blessed($value[0])) {
        unless ($aspect->delegate_view) {
            eval {
                $aspect->generate_delegate_view;
            };
            if ($@) {
                warn $@;
            }
        }
    }
    
    # Delegate to a subordinate view if needed.
    # This means we replace the value(s) with their
    # subordinate widget content.
    my $aspect_text = '';
    if (my $delegate_view = $aspect->delegate_view) {
        $aspect_text .= $self->_indent($indent_text,"<aspect name=\"$aspect_name\">\n");
        foreach my $value ( @value ) {
            $delegate_view->subject($value);
            $delegate_view->_update_view_from_subject();
            $value = $delegate_view->content();
            $value = $self->_indent($indent_text . $indent_text,$value);
            $aspect_text .= $value;
        }
        $aspect_text .= $self->_indent($indent_text,"</aspect>\n");
    }
    else {
        $aspect_text .= $indent_text . "<aspect name=\"$aspect_name\">";
#        if (@value < 2) {
#            if ($value[0] !~ /\n/) {
#                # single value, no newline
#                $aspect_text .= $value[0];
#            }
#            else {
#                # single value with newlines
#                $aspect_text .= 
#                    "\n" 
#                    . $self->_indent($indent_text . $indent_text, $value[0]) 
#            }
#        }
#        else {
        {
            $aspect_text .= "\n";

#            my $d = XML::Dumper->new;

#            $aspect_text .= $self->_indent($indent_text . $indent_text, $d->pl2xml(\@value));
            for my $value (@value) {

                if (ref($value)) {
                    my $d = XML::Dumper->new;
                    my $xmlrep = $d->pl2xml($value);

                    $aspect_text .= $self->_indent($indent_text . $indent_text, $xmlrep); 
                } else {
                    $aspect_text .= $indent_text . $indent_text . "<value>\n";
                    $aspect_text .= $self->_indent($indent_text . $indent_text, $value);
                    $aspect_text .= $indent_text . $indent_text . "</value>\n";
                }
#                if ($value !~ /\n/) {
#                    # multi-value no newline(s)
#                    $aspect_text .= $indent_text . $indent_text . "<value>$value</value>\n";
#                }
#                else {
                    # multi-value with newline(s)
#                    $aspect_text .= $self->_indent($indent_text . $indent_text, $value) 
#                }
            }
            $aspect_text .= $indent_text;
        }
        $aspect_text .= "</aspect>\n";
    }



    return $aspect_text;
}

# Do not return any aspects by default if we're embedded in another view
# The creator of the view will have to specify them manually
sub _resolve_default_aspects {
    my $self = shift;
    unless ($self->parent_view) {
        return $self->SUPER::_resolve_default_aspects;
    }
    return;
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

