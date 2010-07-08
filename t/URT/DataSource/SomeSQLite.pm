
package URT::DataSource::SomeSQLite;
use strict;
use warnings;

use File::Temp;
BEGIN {
    my $fh = File::Temp->new(TEMPLATE => 'ur_testsuite_db_XXXX',
                             UNLINK => 0,
                             SUFFIX => '.sqlite3',
                             OPEN => 0,
                             TMPDIR => 1);
    our $FILE = $fh->filename();
    $fh->close();
    # The DB file now exists with 0 size
}

use UR::Object::Type;
use URT;
class URT::DataSource::SomeSQLite {
    is => ['UR::DataSource::SQLite'],
    type_name => 'urt datasource somesqlite',
};

END {
    my @paths_to_remove = map { __PACKAGE__->$_ } qw(_database_file_path _data_dump_path _schema_path);
    unlink(@paths_to_remove);
}

# Standard behavior is to put the DB file right next to the module
#sub server { $FILE }

# We'll change that...  _database_file_path() is called by server()
sub _database_file_path {
    our $FILE;
    return $FILE;
}


sub owner { undef }

sub login { "gscguest" }

sub auth { "guest_dev" }

1;
