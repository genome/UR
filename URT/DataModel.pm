package URT::DataModel;

use strict;
use warnings;

use URT;
class URT::DataModel {
    type_name => 'data model',
    table_name => 'DATA_MODEL',
    id_by => [
        id => { is => 'Integer' },
    ],
    has => [
        subject_name          => { is => 'Text', is_optional => 1 },
        name                  => { is => 'Text', is_optional => 1 },
        processing_profile_id => { is => 'Integer', is_optional => 1 },
    ],
    schema_name => 'TestMe',
    data_source => 'URT::DataSource::TestMe',
};

1;
