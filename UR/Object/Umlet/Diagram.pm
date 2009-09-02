use strict;
use warnings;

package UR::Object::Umlet::Diagram;

use UR;

use IO::File;
use XML::Simple;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    is => 'UR::Object::Umlet',
    has => [
               name => { type => 'String' },
           ],
    id_by => ['name'],
    doc => 'Represents an entire umlet diagram',
);


sub _class_creating_class { 'UR::Object::Umlet::Class' };
sub _relation_creating_class { 'UR::Object::Umlet::Relation' };

sub create_from_file {
my($class,$filename) = @_;

    unless ($filename) {
        $class->errer_message('arg 1 of create_from_file must be a file name');
        return;
    }
    unless (-f $filename) {
        $class->error_message("file $filename does not exist");
        return;
    }

    my $fh = IO::File->new($filename);
    unless ($fh) {
        $class->error_message("Can't open $filename for reading: $!");
        return;
    }

    my $self = $class->create(name => $filename);
    unless ($self) {
        $class->error_message("Couldn't create new UR::Object::Umlet::Diagram");
        return;
    }

    my $data = XML::Simple::XMLin($filename);
    # If there's only one element in the XML file, it'll get returned as
    # a hash, not a list of hashes
    if (ref($data->{'element'}) eq 'HASH') {
        $data->{'element'} = [ $data->{'element'} ];
    }

    foreach my $element ( @{$data->{'element'}} ) {
        if ($element->{'type'} eq 'com.umlet.element.base.Class') {
            UR::Object::Umlet::Class->create_from_element(diagram_name => $self->name, element => $element);
        } elsif ($element->{'type'} eq 'com.umlet.element.base.Relation') {
            UR::Object::Umlet::Relation->create_from_element(diagram_name => $self->name, element => $element);
        } else {
            UR::Object::Umlet::Other->create_from_element(diagram_name => $self->name, element => $element);
        }
    }

    return $self;
}



sub create_class {
my($self,%params) = @_;
    my $class = $self->_class_creating_class();
    $class->create(%params, diagram => $self->name);
}

sub create_relation {
my($self,%params) = @_;
    my $class = $self->_relation_creating_class();
    $class->create(%params, diagram => $self->name);
}
    

sub save_to_file {
my($self,$filename) = @_;

    my $xml = qq(<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n<umlet_diagram>\n);

    my @objects = UR::Object::Umlet::PictureElement->get(diagram_name => $self->name);
    foreach my $obj ( @objects ) {
        $xml .= $obj->as_xml;
    }
    
    $xml .= "</umlet_diagram>\n";

    my $fh = IO::File->new(">$filename");
    unless ($fh) {
        $self->error_message("Can't write to $filename: $!");
        return;
    }
    $fh->print($xml);
    $fh->close;
}


    
    

1;
