package UR::Object::Property::View::ReferenceDescription::Text;

use strict;
use warnings;
require UR;
our $VERSION = "0.33"; # UR $VERSION;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::View::Default::Text',
    doc => "View used by 'ur describe' for each object-accessor property",
);

sub _update_view_from_subject {
    my $self = shift;

    my $property_meta = $self->subject;
    return unless ($property_meta);

    my $r_class_name = $property_meta->data_type;

    my @relation_detail;
    foreach my $pair ( $property_meta->get_property_name_pairs_for_join() ) {
        my($property_name, $r_property_name) = @$pair;
        push @relation_detail, "$r_property_name => \$self->$property_name";
    }
    my $padding = length($r_class_name) + 34;
    my $relation_detail = join(",\n" . " "x$padding, @relation_detail);


    my $text = sprintf("  %22s => %s->get(%s)\n",
                       $property_meta->property_name,
                       $r_class_name,
                       $relation_detail);
    my $widget = $self->widget();
    my $buffer_ref = $widget->[0];
    $$buffer_ref = $text;
    return 1;
}



1;

=pod

=head1 NAME 

UR::Object::Property::View::DescriptionLineItem::Text - View class for UR::Object::Property

=head1 DESCRIPTION

Used by UR::Namespace::Command::Describe when displaying information about a property

=cut
