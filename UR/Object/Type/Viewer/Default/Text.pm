package UR::Object::Type::Viewer::Default::Text;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::Viewer::Default::Text',
    has => [
       default_aspects => { is => 'ARRAY', is_constant => 1, value => ['is','direct_property_names'], },
    ],
);


1;

