use strict;
use warnings;

package UR::DataSource::RDBMS::TableColumn;

use UR;
UR::Object::Type->define(
    class_name => 'UR::DataSource::RDBMS::TableColumn',
    is => ['UR::Entity'],
    english_name => 'dd table column',
    dsmap => 'dd_table_column',
    er_role => '',
    id_properties => [qw/data_source owner table_name column_name/],
    properties => [
        column_name                      => { type => 'varchar', len => undef, sql => 'column_name' },
        data_source                      => { type => 'varchar', len => undef, sql => 'data_source' },
        owner                            => { type => 'varchar', len => undef, is_optional => 1, sql => 'owner' },
        table_name                       => { type => 'varchar', len => undef, sql => 'table_name' },
        data_length                      => { type => 'varchar', len => undef, is_optional => 1, sql => 'data_length' },
        data_type                        => { type => 'varchar', len => undef, sql => 'data_type' },
        last_object_revision             => { type => 'timestamp', len => undef, sql => 'last_object_revision' },
        nullable                         => { type => 'varchar', len => undef, sql => 'nullable' },
        remarks                          => { type => 'varchar', len => undef, is_optional => 1, sql => 'remarks' },
    ],
    data_source => 'UR::DataSource::Meta',
);

# Methods moved over from the old App::DB::TableColumn

sub _fk_constraint_class {
    my $self = shift;

    if (ref($self) =~ /::Ghost$/) {
        return "UR::DataSource::RDBMS::FkConstraint::Ghost"
    }
    else {
        return "UR::DataSource::RDBMS::FkConstraint"
    }
}


sub generic_data_type {
die "See where this is called from";
    use vars qw(%generic_data_type_for_vendor_data_type);
    return $generic_data_type_for_vendor_data_type{$_[0]->data_type};
}


sub get_table {
    my $self = shift;

    my $table_name = $self->table_name;
    my $data_source = $self->data_source;
    $data_source or Carp::confess("Can't determine data_source for table $table_name column ".$self->column_name );
    my $table =
        UR::DataSource::RDBMS::Table->get(table_name => $table_name, data_source => $data_source)
        ||
        UR::DataSource::RDBMS::Table::Ghost->get(table_name => $table_name, data_source => $data_source);
    return $table;
}


sub fk_constraint_names {

    my @fks = shift->fk_constraints;
    return map { $_->fk_constraint_name } @fks;
}


sub fk_constraints {
    my $self = shift;

    my $fk_class = $self->_fk_constraint_class();
    my @fks = $fk_class->get(table_name => $self->table_name,
                             data_source => $self->data_source,
                             column_name => $self->column_name);
    return @fks;
}


sub resolve_names {
    Carp::carp("resolve_names probably isn't needed anymore");
    return 1;
}


sub bitmap_index_names {
Carp::confess("not implemented yet?!");
}


1;
#$Header
