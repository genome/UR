package URT::DataSource::TestMe;

use strict;
use warnings;

use URT;

class URT::DataSource::TestMe {
    is => [ 'UR::DataSource::SQLite', 'UR::Singleton' ],
};

sub server { '/gscuser/ssmith/svn/pm/URT/DataSource/TestMe.sqlite3' }

1;
