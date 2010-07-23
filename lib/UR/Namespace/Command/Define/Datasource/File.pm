package UR::Namespace::Command::Define::Datasource::File;

use strict;
use warnings;
use UR;

use IO::File;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command::Define::Datasource',
    has => [
                server => {
                    is => 'String',
                    doc => '"server" attribute for this data source, such as a database name',
                },
                nosingleton => {
                    is => 'Boolean',
                    doc => 'Created data source should not inherit from UR::Singleton (defalt is that it will)',
                    default_value => 0,
                },
           ],
           doc => '(Not yet implemented)',
);

sub help_description {
   "Define a UR datasource connected to a file";
}

sub help_brief {
    'Add a file-based data source (not yet implemented)';
}

    
sub execute {
    my $self = shift;

    $self->_init or return;

    $self->warning_message("This command is not yet implemented.  See the documentation for UR::DataSource::File for more information about creating file-based data sources");
    return;
}

1;

