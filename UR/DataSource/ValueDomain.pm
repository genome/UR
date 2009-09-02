package UR::DataSource::ValueDomain;
use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::DataSource::ValueDomain',
    is => ['UR::DataSource'],
    is_abstract => 1,
    properties => [
    ],
    doc => 'A logical DBI-based database, independent of prod/dev/testing considerations or login details.',
);


sub get_objects_for_rule {        
    my $class = shift;    
    my $rule = shift;
    my $obj = $class->create_object($rule);
    $obj->signal_change("define");
    return $obj;
}

1;
