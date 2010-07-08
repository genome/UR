
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
# We'll change that to point to the temp file
sub server {
    our $FILE;
    return $FILE;
}


sub owner { undef }

1;
