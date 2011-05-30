package UR::Value::View::Default::Xml;
use strict;
use warnings;
use UR;

class UR::Value::View::Default::Xml {
    is => ['UR::Object::View::Default::Xml', 'UR::Value::View::Default::Text'],
};

sub _generate_content {
    my $self = shift;
    my $content = $self->UR::Value::View::Default::Text::_generate_content(@_);
    return $content; 
}

1;
