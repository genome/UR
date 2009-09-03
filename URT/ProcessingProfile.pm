package URT::ProcessingProfile;

use strict;
use warnings;

use URT;
class URT::ProcessingProfile {
    type_name => 'processing profile',
    table_name => 'PROCESSING_PROFILE',
    id_by => [
        id => { is => 'Integer' },
    ],
    has => [
        name   => { is => 'Text', is_optional => 1 },
        param1 => { is => 'Text', is_optional => 1 },
        param2 => { is => 'Text', is_optional => 1 },
    ],
    schema_name => 'TestMe',
    data_source => 'URT::DataSource::TestMe',
};

1;
