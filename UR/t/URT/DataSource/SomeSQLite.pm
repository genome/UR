
package URT::DataSource::SomeSQLite;
use strict;
use warnings;

use UR::Object::Type;
use URT;
class URT::DataSource::SomeSQLite {
    is => ['UR::DataSource::SQLite'],
    type_name => 'urt datasource somesqlite',
};

our $FILE = "/tmp/ur_testsuite_db_$$.sqlite";
unlink $FILE if -e $FILE;

sub server { $FILE }

sub owner { undef }

sub login { "gscguest" }

sub auth { "guest_dev" }

1;
