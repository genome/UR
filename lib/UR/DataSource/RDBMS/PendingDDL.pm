use strict;
use warnings;

package UR::DataSource::RDBMS::PendingDDL;

use UR;
UR::Object::Type->define(
    class_name => 'UR::DataSource::RDBMS::PendingDDL',
    is => ['UR::DataSource::RDBMS::Entity'],
    id_by => [
        table => {
            is => 'UR::DataSource::RDBMS::Table',
            id_by => [qw/data_source owner table_name/],
        },
        src => { is => 'Text' },
    ],
    data_source => 'UR::DataSource::Meta',
);


1;

=pod

=head1 NAME

UR::DataSource::RDBMS::PendingDDL - logged changes in DDL

=head1 DESCRIPTION

This class represents instances of columns in a data source's tables.  They are
maintained by 'ur update classes' and stored in the namespace's MetaDB.

=cut

