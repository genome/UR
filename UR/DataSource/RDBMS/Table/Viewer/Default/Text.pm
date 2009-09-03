package UR::DataSource::RDBMS::Table::Viewer::Default::Text;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::Viewer::Default::Text',
    has => [
        default_aspects => { is => 'ARRAY', is_constant => 1, value => ['table_name', 'data_source', 'column_names'] },
    ],
);


1;
