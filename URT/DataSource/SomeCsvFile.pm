
package URT::DataSource::SomeCsvFile;
use strict;
use warnings;

use UR::Object::Type;
use URT;
class URT::DataSource::SomeCsvFile {
    is => ['UR::DataSource::SortedCsvFile'],
    type_name => 'urt datasource somecsvfile',
};

our $FILE = "/tmp/ur_testsuite_db_$$.csv";
unlink $FILE if -e $FILE;

sub server { $FILE }

sub column_order {
    return qw( thing_id thing_name thing_color );
}

sub sort_order {
    return qw( thing_id );
}

sub delimiter { "\t" }


1;
