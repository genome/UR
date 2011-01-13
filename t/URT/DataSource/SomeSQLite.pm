
package URT::DataSource::SomeSQLite;
use strict;
use warnings;

use File::Temp;

use UR::Object::Type;
use URT;
class URT::DataSource::SomeSQLite {
    is => ['UR::DataSource::SQLite'],
    type_name => 'urt datasource somesqlite',
};

# Standard behavior is to put the DB file right next to the module
# We'll change that to point to the temp file
sub server {
    my $self = shift;
    our $PATH;

    $PATH ||= File::Temp->new(TEMPLATE => 'ur_testsuite_db_XXXX',
                              UNLINK => 1,
                              SUFFIX => $self->_extension_for_db,
                              OPEN => 0,
                              TMPDIR => 1);
    return $PATH->filename;
}

1;
