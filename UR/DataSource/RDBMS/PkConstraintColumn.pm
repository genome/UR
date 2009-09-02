use strict;
use warnings;

package UR::DataSource::RDBMS::PkConstraintColumn;

use UR;
UR::Object::Type->define(
    class_name => 'UR::DataSource::RDBMS::PkConstraintColumn',
    is => ['UR::Entity'],
    english_name => 'dd pk constraint column',
    dsmap => 'dd_pk_constraint_column',
    er_role => '',
    id_properties => [qw/data_source owner table_name column_name rank/],
    properties => [
        column_name                      => { type => 'varchar', len => undef, sql => 'column_name' },
        data_source                      => { type => 'varchar', len => undef, sql => 'data_source' },
        owner                            => { type => 'varchar', len => undef, is_optional => 1, sql => 'owner' },
        rank                             => { type => 'integer', len => undef, sql => 'rank' },
        table_name                       => { type => 'varchar', len => undef, sql => 'table_name' },
    ],
    data_source => 'UR::DataSource::Meta',
);

1;
#$Header
