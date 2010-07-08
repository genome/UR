package Vending::DataSource::Machine;

use strict;
use warnings;

use Vending;

class Vending::DataSource::Machine {
    is => [ 'UR::DataSource::SQLite', 'UR::Singleton' ],
};

use File::Temp;
sub server {
    our $FILE;
    unless ($FILE) {
        (undef, $FILE) = File::Temp::tempfile('ur_testsuite_vend_XXXX',
                                              OPEN => 0,
                                              UNKINK => 0,
                                              TMPDIR => 1,
                                              SUFFIX => '.sqlite3');
        print STDERR "Using DB file $FILE\n";
    }
    return $FILE;
}

END {
    our $FILE;
    unlink $FILE;
}


1;
