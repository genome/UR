
package URT::DataSource::CircFk;
use strict;
use warnings;

use UR::Object::Type;
use URT;
class URT::DataSource::CircFk {
    is => ['UR::DataSource::SQLite'],
    type_name => 'urt datasource somesqlite',
};

our $FILE = "/tmp/ur_testsuite_db_$$.sqlite";
IO::File->new($FILE, 'w')->close();

END { unlink $FILE }

sub _database_file_path { $FILE }

sub owner { undef }

sub login { "gscguest" }

sub auth { "guest_dev" }

1;
