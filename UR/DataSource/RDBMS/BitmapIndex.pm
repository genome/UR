use strict;
use warnings;

package UR::DataSource::RDBMS::BitmapIndex;

use UR;
UR::Object::Type->define(
    class_name => 'UR::DataSource::RDBMS::BitmapIndex',
    is => ['UR::Entity'],
    english_name => 'dd bitmap index',
    dsmap => 'dd_bitmap_index',
    er_role => '',
    id_properties => [qw/data_source owner table_name bitmap_index_name/],
    properties => [
        bitmap_index_name                => { type => 'varchar', len => undef, sql => 'bitmap_index_name' },
        data_source                      => { type => 'varchar', len => undef, sql => 'data_source' },
        data_source_obj                  => { type => 'UR::DataSource', id_by => 'data_source'},
        namespace                        => { type => 'varchar', via => 'data_source_obj', to => 'namespace' },
        owner                            => { type => 'varchar', len => undef, is_optional => 1, sql => 'owner' },
        table_name                       => { type => 'varchar', len => undef, sql => 'table_name' },
    ],
    data_source => 'UR::DataSource::Meta',
);

1;
#$Header
