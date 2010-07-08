package Vending::DataSource::Machine;

use strict;
use warnings;

use Vending;

class Vending::DataSource::Machine {
    is => [ 'UR::DataSource::SQLite', 'UR::Singleton' ],
};

1;
