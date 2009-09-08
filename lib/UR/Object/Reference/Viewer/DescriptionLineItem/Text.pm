package UR::Object::Reference::Viewer::DescriptionLineItem::Text;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::Viewer::Default::Text',
    doc => "Viewer used by 'ur describe' for each reference (relationship) line item",
);

sub _update_widget_from_subject {
    my $self = shift;

    my $ref_meta = $self->get_subject;
    my $r_class_name = $ref_meta->r_class_name;

    my @relation_detail;
    foreach my $ref_prop ( $ref_meta->reference_property_metas ) {
        my $property_name = $ref_prop->property_name;
        my $r_property_name = $ref_prop->r_property_name;
        push @relation_detail,"$r_property_name => \$self->$property_name";
    }
    my $relation_detail = join(",\n" . " "x28, @relation_detail);

    my $text = sprintf("\n    %20s => %s->get(%s)",
                       $ref_meta->delegation_name,
                       $r_class_name,
                       $relation_detail);
    $self->buf($text);
    return 1;
}



1;

=pod

=head1 NAME

UR::Object::Reference::Viewer::DescriptionLineItem::Text - Viewer class for Reference objects

=head1 DESCRIPTION

This class is used by L<UR::Namespace::Command::Describe> to print detail
about indirect properties.

=cut


