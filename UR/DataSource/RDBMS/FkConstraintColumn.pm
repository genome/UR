use strict;
use warnings;

package UR::DataSource::RDBMS::FkConstraintColumn;

use UR;
UR::Object::Type->define(
    class_name => 'UR::DataSource::RDBMS::FkConstraintColumn',
    is => ['UR::Entity'],
    english_name => 'dd fk constraint column',
    dsmap => 'dd_fk_constraint_column',
    er_role => 'bridge',
    id_properties => [qw/data_source owner table_name fk_constraint_name column_name/],
    properties => [
        column_name                      => { type => 'varchar', len => undef, sql => 'column_name' },
        data_source                      => { type => 'varchar', len => undef, sql => 'data_source' },
        fk_constraint_name               => { type => 'varchar', len => undef, sql => 'fk_constraint_name' },
        owner                            => { type => 'varchar', len => undef, sql => 'owner' },
        table_name                       => { type => 'varchar', len => undef, sql => 'table_name' },
        r_column_name                    => { type => 'varchar', len => undef, sql => 'r_column_name' },
        r_table_name                     => { type => 'varchar', len => undef, sql => 'r_table_name' },
    ],
    data_source => 'UR::DataSource::Meta',
);

1;
#$Header

