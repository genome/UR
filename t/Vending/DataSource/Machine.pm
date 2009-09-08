package Vending::DataSource::Machine;

use strict;
use warnings;

use Vending;

class Vending::DataSource::Machine {
    is => [ 'UR::DataSource::SQLite', 'UR::Singleton' ],
};

#sub server { '/gscuser/abrummet/svk/perl_modules/Vending/DataSource/Machine.sqlite3' }

1;
