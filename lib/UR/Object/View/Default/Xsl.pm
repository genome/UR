package UR::Object::View::Default::Html;

use strict;
use warnings;
use IO::File;

class UR::Object::View::Default::Xsl {
    is => 'UR::Object::View::Default::Text',
    has => [
        output_format => { value => 'html' },
        xsl_path => {
            doc => 'absolute path where xsl files will be found, expected ' .
                   'format is $xsl_path/$output_format/$perspective/' .
                   '$normalized_class_name.xsl'
        },
    ]
};

sub _generate_content {
    my $self = shift;

    my $subject = $self->subject;
    return unless $subject;

    unless ($self->xsl_path && -e $self->xsl_path) {
        die 'xsl_path does not exist';
    }

    # get the xml for the equivalent perspective
    $DB::single = 1;
    my $xml_view = $subject->create_view(
        perspective => $self->perspective,
        toolkit => 'xml',
    );   
    my $xml_content = $xml_view->_generate_content();

    # subclasses typically have this as a constant value
    # it turns out we don't need it, since the file will be HTML.pm.xsl for xml->html conversion
    # my $toolkit = $self->toolkit;

    my $parser = XML::LibXML->new;
    my $xslt = XML::LibXSLT->new;

    my $output_format = $self->output_format;
    my $xsl_path = $self->xsl_path; 

    my @include_files = $xml_view->xsl_template_files(
        $output_format,
        $xsl_path . '/'
    );

    my @includes = map {
      "<xsl:include href=\"$xsl_path/$_\"/>\n";
    } @include_files;

    my $perspective = $self->perspective;
    my $xsl_template = <<STYLE;
<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0"
xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:variable name="rest">/cgi-bin/rest.cgi</xsl:variable>
  <xsl:variable name="xsl">/cgi-bin/xsl.cgi</xsl:variable>
  <xsl:variable name="currentPerspective">$perspective</xsl:variable>
  <xsl:variable name="currentToolkit">html</xsl:variable>
  <xsl:include href="$xsl_path/$output_format/$perspective/root.xsl"/>
@includes
</xsl:stylesheet>
STYLE

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

