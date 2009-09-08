package UR::DataSource::RDBMS::Table::Viewer::Default::Text;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::Viewer::Default::Text',
    has => [
        default_aspects => { is => 'ARRAY', is_constant => 1, value => ['table_name', 'data_source', 'column_names'] },
    ],
);


1;

=pod

=head1 NAME

UR::DataSource::RDBMS::Table::Viewer::Default::Text - Viewer class for RDBMS table objects

=head1 DESCRIPTION

This class defines a text-mode viewer for RDBMS table objects, and is used by
the 'ur info' command.

=cut
