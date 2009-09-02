use strict;
use warnings;

package UR::Object::Umlet::Relation;

use UR;

use IO::File;
use XML::Simple;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    is => 'UR::Object::Umlet::PictureElement',
    has => [
               width => { type => 'Integer' },
               height => { type => 'Integer'}, 

               relation_type => { type => 'String' },
               head_multiplicity => { type => 'String', is_optional => 1 },
               tail_multiplicity => { type => 'String', is_optional => 1 },
               head_qualifier => { type => 'String', is_optional => 1 },
               tail_qualifier => { type => 'String', is_optional => 1 },
               head_role => { type => 'String', is_optional => 1 },
               tail_role => { type => 'String', is_optional => 1 },

               head_x_offset => { type => 'Integer' },
               head_y_offset => { type => 'Integer' },
               tail_x_offset => { type => 'Integer' },
               tail_y_offset => { type => 'Integer' },
               waypoints => { type => 'Object', is_optional => 1 },

               from_entity_name => { type => 'String' },
               to_entity_name => { type => 'String' },
               from_attribute_name => { type => 'String', is_optional => 1},
               to_attribute_name => { type => 'String', is_optional => 1},
              
          
           ],
);


sub create {
my($class, %params) = @_;

    unless (exists $params{'subject_id'}) {
        no warnings;
        $params{'subject_id'} = join(';', @params{'from_entity_name','to_entity_name','from_attribute_name','to_attribute_name'});
    }
    return $class->SUPER::create(%params);
}

sub umlet_type_string { return 'com.umlet.element.base.Relation' };
    
sub create_from_element {
my($class,%params) = @_;

    my $addl = delete $params{'element'}->{'additional_attributes'};
    my %addl = $class->_parse_additional_attributes($addl);

    my $self = $class->SUPER::create_from_element(%params, %addl);
    return $self;
}

sub _fixup_panel_attributes {
my($class, %attributes) = @_;

    %attributes = $class->SUPER::_fixup_panel_attributes(%attributes);
    
    $attributes{'relation_type'} = delete $attributes{'lt'};
    $attributes{'head_multiplicity'} = delete $attributes{'m1'};
    $attributes{'tail_multiplicity'} = delete $attributes{'m2'};
    $attributes{'head_qualifier'} = delete $attributes{'q1'};
    $attributes{'tail_qualifier'} = delete $attributes{'q2'};
    $attributes{'head_role'} = delete $attributes{'r1'};
    $attributes{'tail_role'} = delete $attributes{'r2'};

    @attributes{'from_entity_name','to_entity_name','from_attribute_name','to_attribute_name'} = split(';',$attributes{'subject_id'});

    return %attributes;
}


sub _parse_additional_attributes {
my($class,$string) = @_;
    my @points = split(';', $string);

    my %retval;

    # The format is head_x ; head_y ; waypoint_x; waypoint_y; tail_x; tail_y
    # And you can have 0 or more waypoints
    $retval{'head_x_offset'} = shift @points;
    $retval{'head_y_offset'} = shift @points;
    $retval{'tail_y_offset'} = pop @points;
    $retval{'tail_x_offset'} = pop @points;

    $retval{'waypoints'} = \@points;

    return %retval;
}
    
    
our %attr_map = ( head_multiplicity => 'm1', tail_multiplicity => 'm2',
                  head_qualifier => 'q1', tail_qualifier => 'q1',
                  head_role => 'r1', tail_role => 'r2',
                );

sub panel_attributes {
my($self) = @_;
   
    my $string = '';

    if ($self->label) {
        $string .= $self->label."\n";
    }

    $string .= "lt=" . $self->relation_type . "\n";

    foreach my $key ( keys %attr_map ) {
        my $value = $self->$key();
        if (defined $value) {
            my $attr = $attr_map{$key};
            $string .= "$attr=$value\n";
        }
    }
    my $id_string = join(';', $self->from_entity_name, $self->to_entity_name,
                              $self->from_attribute_name || '', $self->to_attribute_name || '');
    $string .= "//subject_id:$id_string\n";

    $string = $self->escape_xml_data($string);
    return "<panel_attributes>$string</panel_attributes>\n";;
}

    

sub additional_attributes {
my($self) = @_;

    my @points = ($self->head_x_offset, $self->head_y_offset);
    if ($self->waypoints && scalar @{ $self->waypoints } ) {
        push @points, @{ $self->waypoints };
    }
    push @points, ($self->tail_x_offset, $self->tail_y_offset);

    return "<additional_attributes>" . join(';', @points) . "</additional_attributes>\n";
}


sub connect_entities {
my $self = shift;

    my $from_entity = UR::Object::Umlet::Class->get(diagram_name => $self->diagram_name,
                                                    subject_id => $self->from_entity_name);
    my $to_entity   = UR::Object::Umlet::Class->get(diagram_name => $self->diagram_name,
                                                    subject_id => $self->to_entity_name);
    return unless ($from_entity and $to_entity);

    # The coords for both ends of the arrow
    my($head_x_coord, $head_y_coord, $tail_x_coord, $tail_y_coord);
    if ($from_entity->y > $to_entity->y) {
        $tail_y_coord = $from_entity->y + $from_entity->height;
        $head_y_coord = $to_entity->y;
    } else { 
        $tail_y_coord = $from_entity->y;
        $head_y_coord = $to_entity->y + $to_entity->height; 
    }

    $tail_x_coord = $from_entity->x + int($from_entity->width / 2);
    $head_x_coord = $to_entity->x + int($to_entity->width / 2);

    my $x = ( $head_x_coord < $tail_x_coord ? $head_x_coord : $tail_x_coord ) - 20;
    my $y = ( $head_y_coord < $tail_y_coord ? $head_y_coord : $tail_y_coord ) - 20;
    my $width = abs($head_x_coord - $tail_x_coord) + 40;
    my $height = abs($head_y_coord - $tail_y_coord) + 40;

    my $head_x_offset =  $head_x_coord - $x;
    my $head_y_offset =  $head_y_coord - $y;
    my $tail_x_offset = $tail_x_coord - $x;
    my $tail_y_offset = $tail_y_coord - $y;

    $self->x($x);
    $self->y($y);
    $self->width($width);
    $self->height($height);
    $self->head_x_offset($head_x_offset);
    $self->head_y_offset($head_y_offset);
    $self->tail_x_offset($tail_x_offset);
    $self->tail_y_offset($tail_y_offset);
    
    return 1;
}

sub connect_entity_attributes {
my $self = shift;

    my $from_entity = UR::Object::Umlet::Class->get(diagram_name => $self->diagram_name,
                                                    subject_id => $self->from_entity_name);
    my $to_entity   = UR::Object::Umlet::Class->get(diagram_name => $self->diagram_name,
                                                    subject_id => $self->to_entity_name);
    return unless ($from_entity and $to_entity);

    my $from_attribute_pos = 0;
    foreach my $attr ( @{ $from_entity->attributes } ) {
        if ($attr->{'name'} eq $self->from_attribute_name) {
            $from_attribute_pos = ($attr->{'line'}) * 18;
            last;
        }
    }

    my $to_attribute_pos = 0;
    foreach my $attr ( @{ $to_entity->attributes } ) {
        if ($attr->{'name'} eq $self->to_attribute_name) {
            $to_attribute_pos = ($attr->{'line'}) * 18;
            last;
        }
    }

    # The coords for both ends of the arrow
    my($head_x_coord, $head_y_coord, $tail_x_coord, $tail_y_coord);
    $tail_y_coord = $from_entity->y + $from_attribute_pos;
    $head_y_coord = $to_entity->y + $to_attribute_pos;

    if ($from_entity->x < $to_entity->x) {
        $tail_x_coord = $from_entity->x + $from_entity->width;
        $head_x_coord = $to_entity->x;
    } elsif ($from_entity->x > $to_entity->x) {
        $tail_x_coord = $from_entity->x;
        $head_x_coord = $to_entity->x + $to_entity->width;
    } else {
        $tail_x_coord = $from_entity->x;
        $head_x_coord = $to_entity->x;
    }

    my $x = ( $head_x_coord < $tail_x_coord ? $head_x_coord : $tail_x_coord ) - 20;
    my $y = ( $head_y_coord < $tail_y_coord ? $head_y_coord : $tail_y_coord ) - 20;
    my $width = abs($head_x_coord - $tail_x_coord) + 40;
    my $height = abs($head_y_coord - $tail_y_coord) + 40;

    my $head_x_offset =  $head_x_coord - $x;
    my $head_y_offset =  $head_y_coord - $y;
    my $tail_x_offset = $tail_x_coord - $x;
    my $tail_y_offset = $tail_y_coord - $y;

    $self->x($x);
    $self->y($y);
    $self->width($width);
    $self->height($height);
    $self->head_x_offset($head_x_offset);
    $self->head_y_offset($head_y_offset);
    $self->tail_x_offset($tail_x_offset);
    $self->tail_y_offset($tail_y_offset);
 
    return 1;
}

1;
