use strict;
use warnings;

package UR::Object::Umlet::Other;

use UR;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    is => 'UR::Object::Umlet::PictureElement',
    has => [
               width => { type => 'Integer' },
               height => { type => 'Integer' },
               panel_attributes_data => { type => 'String'},
               additional_attributes_data => { type => 'String'},
               umlet_type_string => { type => 'String' },
           ],
);

# This class represents Umlet objects we don't care to manipulate
# other than to preserve them in existing diagrams

our $subject_id = 1;   # Auto-generate subject IDs

sub create_from_element {
my($class,%params) = @_;
    my $element = delete $params{'element'};
    my $panel_attributes_data = delete $element->{'panel_attributes'};
    my $additional_attributes_data = delete $element->{'additional_attributes'};
    my $type = delete $element->{'type'};

    # Because of a pecularity of XML::Simple, empty XML elements atr translated into
    # Perl as an empty hash.  Change this to undef
    $panel_attributes_data = undef if (ref($panel_attributes_data) eq 'HASH' and
                                       scalar(keys %$panel_attributes_data) == 0);
    $additional_attributes_data = undef if (ref($additional_attributes_data) eq 'HASH' and
                                       scalar(keys %$additional_attributes_data) == 0);

    my $self = $class->SUPER::create_from_element(panel_attributes_data => $panel_attributes_data,
                                                  additional_attributes_data => $additional_attributes_data,
                                                  umlet_type_string => $type,
                                                  element => $element,
                                                  subject_id => $subject_id++,
                                                  %params,
                                                );
    return $self;
}


sub panel_attributes {
my($self) = @_;
    my $data = $self->panel_attributes_data();

    if ($data) {
        return "<panel_attributes>$data</panel_attributes>";
    } else {
        return "<panel_attributes/>";
    }
}

sub additional_attributes {
my($self) = @_;
    my $data = $self->additional_attributes_data();

    if ($data) {
        return "<additional_attributes>$data</additional_attributes>";
    } else {
        return "<additional_attributes/>";
    }
}


1;
