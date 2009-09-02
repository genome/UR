
package URT::DataSource::SomePostgres;
use strict;
use warnings;

use UR::Object::Type;
use URT;
class URT::DataSource::SomePostgres {
    is => ['UR::DataSource::Oracle'],
    type_name => 'urt datasource somepostgres',
};

sub server { "dwdev" }

sub owner { "GSC" }

sub login { "gscguest" }

sub auth { "guest_dev" }

1;
