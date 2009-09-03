package UR::DataSource::Meta;

# The datasource for metadata describing the tables, columns and foreign
# keys in the target datasource

use strict;
use warnings;

use UR;

UR::Object::Type->define(
    class_name => 'UR::DataSource::Meta',
    is => ['UR::DataSource::SQLite'],
);

sub _resolve_class_name_for_table_name_fixups {
    my $self = shift->_singleton_object;

    if ($_[0] =~ m/Dd/) {
        $_[0] = "DataSource::RDBMS::";
    }

    #return $self->class . "::", @_;
    return @_;
}

# Do a DB dump at commit time
sub dump_on_commit {
1;
}

1;

=pod

=head1 NAME

UR::DataSource::Meta - Data source for the MetaDB

=head1 SYNOPSIS

  my $meta_table = UR::DataSource::RDBMS::Table->get(
                       table_name => 'DD_TABLE'
                       namespace => 'UR',
                   );

  my @myapp_tables = UR::DataSource::RDBMS::Table->get(
                       namespace => 'MyApp',
                   );

=head1 DESCRIPTION

UR::DataSource::Meta is a datasource that encompases all the MetaDBs in
the system.  All the MetaDB object types (L<UR::DataSource::RDBMS::Table>,
L<UR::DataSource::RDBMS::TableColumn>, etc) have UR::DataSource::Meta
as their data source.

Internally, the Context looks at the get() parameters for these MetaDB
classes, and switches to other Meta data sources to fulfil the request.
Table information for the MyApp namespace is stored in the
MyApp::DataSource::Meta data source.  Information about the MetaDB schema
is stored in the UR::DataSource::Meta data source.

The MetaDB is a SQLite database stored in the same directory as the Meta.pm
file implementing the data source.

=head1 INHERITANCE

UR::DataSource::Meta is a subclass of L<UR::DataSource::SQLite>

=head1 get() required parameters

C<namespace> or C<data_source> are required parameters when calling C<get()>
on any MetaDB-sourced object types.

=cut
