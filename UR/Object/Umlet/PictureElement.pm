use strict;
use warnings;

package UR::Object::Umlet::PictureElement;

use UR;

use IO::Handle;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    is => 'UR::Object::Umlet',
    has => [
               subject_id => { type => 'String' },
               diagram_name => { type => 'String' },

               label => { type => 'String' },
               x => { type => 'Integer' },
               y => { type => 'Integer' },
               fg_color => { type => 'String' },
               bg_color => { type => 'String' },
           ],
    id_by => ['subject_id','diagram_name'],
    relationships => [
               diagram => { class_name => 'UR::Object::Umlet::Diagram', properties => ['diagram_name'] }
          ],
    is_abstract => 1,
    doc => 'The parent class for parts of an Umlet diagram',
);


sub create_from_element {
my($class, %params) = @_;

    my $element = delete $params{'element'};
    my($x,$y,$width,$height) = ( $element->{'coordinates'}->{'x'},
                                 $element->{'coordinates'}->{'y'},
                                 $element->{'coordinates'}->{'w'},
                                 $element->{'coordinates'}->{'h'},
                               );

    my %attributes = $class->_fixup_panel_attributes($class->_parse_panel_attributes($element->{'panel_attributes'}));

    my $self = $class->create(%params, %attributes,
                              x => $x, y=> $y, width => $width, height => $height,
                              );
    return unless $self;
}


sub _fixup_panel_attributes {
my($class,%attributes) = @_;

    my $fg = delete $attributes{'fg'};
    my $bg = delete $attributes{'bg'};

    return ( %attributes, fg_color => $fg, bg_color => $bg);
}




sub _parse_panel_attributes {
my($self,$string) = @_;
    return unless $string;

    my $fh = IO::Handle->new();

    open($fh, '<', \$string);

    my %attributes;

    my $section_number = 0;
    my $line_number = 0;

    while (my $line = <$fh>) {
        chomp($line);

        if ($line =~ m(^//subject_id:(\S+)) ) {
            $attributes{'subject_id'} = $1;

        } elsif ($line =~ m/^(\w\w)=(.*)$/) {
            $attributes{$1} = $2;
 
        } elsif ($line eq '--') {
            $section_number++;
   
        } else {
            if ($section_number == 0) {
                $attributes{'label'} .= "$line\n";

            } elsif ($section_number == 1) {
                my($is_id,$attr,$type) = ($line =~ m/^(\W)?(\S+): (\S+)/);
                #$is_id = undef if ($is_id eq ' ');
                push(@{$attributes{'attributes'}}, { is_id => $is_id, name => $attr, type => $type, line => $line_number++ });

            } elsif ($section_number == 2) {
                my($type, $name) = ($line =~ m/(\S)(\w+)/);
                push(@{$attributes{'methods'}}, { type => $type, name => $name, line => $line_number++ });

            } else {
                $attributes{'other'} .= "$line\n";
            }
        }
    }

    chomp($attributes{'label'}) if ($attributes{'label'});
    chomp($attributes{'other'}) if ($attributes{'other'});

    return %attributes;
};


sub as_xml {
my($self) = @_;

    my $xml = qq(<element>\n);
    $xml .= sprintf("<type>%s</type>\n", $self->umlet_type_string);
    $xml .= sprintf("<coordinates>\n<x>%d</x>\n<y>%d</y>\n<w>%d</w>\n<h>%d</h>\n</coordinates>\n",
                    $self->x, $self->y, $self->width, $self->height);

    $xml .= $self->panel_attributes();

    $xml .= $self->additional_attributes();

    $xml .= "</element>\n";

    return $xml;
}
                      


# Child classes should override this to write appropriate data
sub panel_attributes { "<panel_attributes/>\n"; }
sub additional_attributes { "<additional_attributes/>\n"; }


# Does the rectangle bounding self and the target overlap?
sub is_overlapping {
my($self,$target) = @_;

    my $self_xmin = $self->x;
    my $self_xmax = $self_xmin + $self->width;
    my $self_ymin = $self->y;
    my $self_ymax = $self_ymin + $self->height;
    
    my $target_xmin = $target->x;
    my $target_xmax = $target_xmin + $target->width;
    my $target_ymin = $target->y;
    my $target_ymax = $target_ymin + $target->height;
 
    if ( $self_xmin > $target_xmax ||
         $target_xmin > $self_xmax ||
         $self_ymin > $target_ymax ||
         $target_ymin > $self_ymax) {
        return 0;
    } else {
        return 1;
    }
}


1;
