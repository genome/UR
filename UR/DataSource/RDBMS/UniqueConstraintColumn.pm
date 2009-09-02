use strict;
use warnings;

package UR::DataSource::RDBMS::UniqueConstraintColumn;

use UR::Object::Type;
UR::Object::Type->define(
    class_name => 'UR::DataSource::RDBMS::UniqueConstraintColumn',
    is => ['UR::Entity'],
    english_name => 'dd_unique_constraint_column',
    dsmap => 'dd_unique_constraint_column',
    id_properties => [qw/data_source owner table_name constraint_name column_name/],
    properties => [
        data_source                      => { type => 'varchar', len => undef, sql => 'data_source' },
        data_source_obj                  => { type => 'UR::DataSource', id_by => 'data_source'},
        namespace                        => { type => 'varchar', via => 'data_source_obj', to => 'namespace' },
        owner                            => { type => 'varchar', len => undef, sql => 'owner', is_optional => 1 },
        table_name                       => { type => 'varchar', len => undef, sql => 'table_name' },
        constraint_name                  => { type => 'varchar', len => undef, sql => 'constraint_name' },
        column_name                      => { type => 'varchar', len => undef, sql => 'column_name' },
    ],
    data_source => 'UR::DataSource::Meta',
);

1;


