package UR::Attribute;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Attribute',
    is => ['UR::Object'],
    english_name => 'ur attribute',
);

sub load {
    my $class = shift;    
    my %params = $class->preprocess_params(@_);
    my $entity_class_name = delete $params{entity_class_name};
    my $entity_property_name = delete $params{entity_property_name};
    my $entity_id = delete $params{entity_id};
    
    $entity_class_name->class;
    my $entity = $entity_class_name->get($entity_id);
}

sub value {
    my $self = shift;
}

1;
#$Header$
