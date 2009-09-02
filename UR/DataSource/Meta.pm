package UR::DataSource::Meta;

# The datasource for metadata describing the tables, columns and foreign
# keys in the target datasource

use strict;
use warnings;

use UR;
use File::Copy qw//;

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
