package UR::Object::Type::Viewer::Default::Umlet;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::Viewer',
);


# These are noops for textual widgets
sub _update_subject_from_widget {
1;}

#sub show {
#my $self = shift;
#
#    print $self->sshow();
#}

sub _create_widget {
    my $string = '';
    return \$string;
}


sub _update_widget_from_subject {
my $self = shift;

    $DB::single=1;

    my $class = $self->get_subject();
    my @aspects = $self->get_aspects();
    my $widget = $self->get_widget();
  
    my $class_name = $class->class_name;
    my $panel_attributes = "$class_name\n--\n";
    my $line_count = 1;

    my %id_properties = map { $_ => 1 } $class->id_property_names;

    foreach my $property_name ( $class->instance_property_names ) {
        $line_count++;
        my $property = UR::Object::Property->get(class_name => $class_name, property_name => $property_name);
        
        $panel_attributes .= sprintf("%s%s: %s\n",
                                     $id_properties{$property_name} ? '+' : ' ',
                                     $property_name,
                                     $property->data_type || '/undef/');
    }
    #$panel_attributes .= "--\n";

    my $width = 200;
    my $height = $line_count * 20;

    $$widget = qq(<element>
<type>com.umlet.element.base.Class</type>
<coordinates>
<x>X_COORDINATE</x>
<y>Y_COORDINATE</y>
<w>$width</w>
<h>$height</h>
</coordinates>
<panel_attributes>$panel_attributes
</panel_attributes>
<additional_attributes/>
</element>
);
}

1;    
