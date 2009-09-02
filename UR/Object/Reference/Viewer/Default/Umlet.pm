package UR::Object::Reference::Viewer::Default::Umlet;

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

    my $inheritance = $self->get_subject();
    my @aspects = $self->get_aspects();
    my $widget = $self->get_widget();
  
    my $string = qq(<element>
<type>com.umlet.element.base.Relation</type>
<coordinates>
<x>X_COORDINATE</x>
<y>Y_COORDINATE</y>
<w>WIDTH</w>
<h>HEIGHT</h>
</coordinates>
<panel_attributes>lt=&lt;-
Arrow 1</panel_attributes>
<additional_attributes>HEAD_X_OFFSET;HEAD_Y_OFFSET;TAIL_X_OFFSET;TAIL_Y_OFFSET</additional_attributes>
</element>
);

    $$widget = $string;
}

1;    
