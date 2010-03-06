package UR::Object::View::Default::Html;

use strict;
use warnings;
use IO::File;

class UR::Object::View::Default::Xsl {
    is => 'UR::Object::View::Default::Text',
    has_optional => [
        xsl_file => { value => 'html' },
    ]
};

sub _generate_content {
    my $self = shift;

    my $subject = $self->subject;
    return unless $subject;

    # get the xml for the equivalent perspective
    $DB::single = 1;
    my $xml_view = $subject->create_view(
        perspective => $self->perspective,
        toolkit => 'xml',

        # custom for this view
        instance_id => $self->instance_id, 
        use_lsf_file => $self->use_lsf_file, 
    );   
    my $xml_content = $xml_view->_generate_content();

    # subclasses typically have this as a constant value
    # it turns out we don't need it, since the file will be HTML.pm.xsl for xml->html conversion
    # my $toolkit = $self->toolkit;

    # get the xsl
    unless ($self->xsl_file) {
        my $view_class_name = $xml_view->__meta__->class_name;
        my $view_module_path  = $INC{$view_class_name};
        die "No path found for view class $view_class_name\n" unless $view_module_path;
        my $xsl_file_expected = $view_module_path . '.xsl';
        die "No XSL file found at $xsl_file_expected" unless -e $xsl_file_expected;
        $self->xsl_file($xsl_file_expected);
    }
    unless (-e $self->xsl_file) {
        die "Failed to find xsl file: " . $self->xsl_file;
    }
    my $parser = XML::LibXML->new;
    my $xslt = XML::LibXSLT->new;
    my @template_lines;
    my $fh = IO::File->new($self->xsl_file);
    while (my $line = $fh->getline()) {
        push @template_lines,$line;
    }
    $fh->close();
    my $xsl_template = join("",@template_lines);

    # convert the xml
    my $source = $parser->parse_string($xml_content);
    my $style_doc = $parser->parse_string($xsl_template);
    my $stylesheet = $xslt->parse_stylesheet($style_doc);
    my $results = $stylesheet->transform($source);
    my $content = $stylesheet->output_string($results);

    return $content;
}

1;


=pod

=head1 NAME

UR::Object::View::Default::Xsl - base class for views which use XSL on an XML view to generate content 

=head1 SYNOPSIS

  #####

  class Acme::Product::View::OrderStatus::Html {
    is => 'UR::Object::View::Default::Xsl',
  }

  #####
  
  Acme/Product/View/OrderStatus/Html.pm.xsl

  #####

  $o = Acme::Product->get(1234);

  $v = $o->create_view(
      perspective => 'order status',
      toolkit => 'html',
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

This class implements basic HTML views of objects.  It has standard behavior for all text views.

=head1 SEE ALSO

UR::Object::View::Default::Text, UR::Object::View, UR::Object::View::Toolkit::XML, UR::Object::View::Toolkit::Text, UR::Object

=cut

