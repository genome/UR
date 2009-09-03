use strict;
use warnings;

package UR::Object::Umlet::Class;

use UR;

use IO::File;
use XML::Simple;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    is => 'UR::Object::Umlet::Other',
    has => [
               attributes => { type => 'Object' },
               methods => { type => 'Object', is_optional => 1 },
               stored_width => { type => 'Integer', is_optional => 1 },
               stored_height => { type => 'Integer', is_optional => 1 },
           ],
    doc => 'Represents one of the box-type items (classes or DB tables) on an umlet diagram',
);

sub umlet_type_string { return 'com.umlet.element.base.Class' };

sub height {
my $self = shift;

    if ($self->stored_height) {
        return $self->stored_height;
    }

    my $count = 1;  # for the class name
    
    if ($self->attributes) {
        $count += scalar ( @{$self->attributes} );
    }

    if ($self->methods) {
        $count += scalar ( @{$self->methods} );
    }
    $count *= 20;

    $count = int($count / 10) * 10;
    return $count < 20 ? 20 : $count;
 
}

sub width {
my $self = shift;
    if ($self->stored_width) {
        return $self->stored_width;
    }

    my $width = length($self->label);
   
    my $attributes = $self->attributes || [];
    foreach my $attr ( @$attributes ) {
        no warnings;  # Some attributes below can be undef
        my $string = join(' ',@$attr{'is_id','name','type'});
        my $length = length $string;
        if ($length > $width) {
            $width = $length;
        }
    }

    my $methods = $self->methods;
    foreach my $method ( @$methods ) {
        my $string = join(' ',@$method{'type','name'});
        my $length = length $string;
        if ($length > $width) {
            $width = $length;
        }
    }

    $width = ($width * 10);
    #if ($width < 200) {
    #    $width = 200;
    #}
    return $width;
}

sub create_from_element {
my($class, %params) = @_;

    my $element = delete $params{'element'};
    my($x,$y,$width,$height) = ( $element->{'coordinates'}->{'x'},
                                 $element->{'coordinates'}->{'y'},
                                 $element->{'coordinates'}->{'w'},
                                 $element->{'coordinates'}->{'h'},
                               );

    my %extra = $class->_fixup_panel_attributes($class->_parse_panel_attributes($element->{'panel_attributes'}));
    my $attributes = delete $extra{'attributes'};
    my $methods = delete $extra{'methods'};

    my $self = $class->create(%params, %extra,
                              x => $x, y=> $y, stored_width => $width, stored_height => $height,
                              );
    $self->attributes($attributes);
    $self->methods($methods);
    return unless $self;
}



sub panel_attributes {
my($self) = @_;

    my $string = '';
    
    if ($self->label) {
        $string .= $self->label."\n";
    }
  
    if ($self->attributes && scalar( @{$self->attributes} )) {
        $string .= "--\n";
        foreach my $attr ( @{ $self->attributes } ) {
            no warnings;  # is_id can be undef
            $string .= sprintf("%s%s: %s\n", @$attr{'is_id','name','type'});
        }
    }

    if ($self->methods && scalar( @{ $self->methods })) {
        $string .= "--\n";
        foreach my $method ( @{ $self->methods } ) {
            $string .= sprintf("%s%s\n", @$method{'type','name'});
        }
    }

    my($fg, $bg) = ($self->fg_color, $self->bg_color);
    $string .= "fg=$fg\n" if (defined $fg);
    $string .= "bg=$bg\n" if (defined $bg);

    $string .= "//subject_id:" . $self->subject_id . "\n";

    $string = $self->escape_xml_data($string);
    return "<panel_attributes>$string</panel_attributes>";
}


1;
