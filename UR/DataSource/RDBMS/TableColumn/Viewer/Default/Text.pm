package UR::DataSource::RDBMS::TableColumn::Viewer::Default::Text;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::Viewer::Default::Text',
    has => [
        default_aspects => { is => 'ARRAY', is_constant => 1, value => ['column_name', 'table_name', 'data_type', 'length', 'nullable'] },
    ],
);


1;
