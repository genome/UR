
package URT::DataSource::SomeFileMux;
use strict;
use warnings;

use UR::Object::Type;
use URT;
class URT::DataSource::SomeFileMux {
    is => ['UR::DataSource::FileMux', 'UR::Singleton'],
    type_name => 'urt datasource somefilemux',
};

sub constant_values { [ 'thing_type' ] }

sub required_for_get { [ 'thing_type' ] }

sub column_order {
    return [ qw( thing_id thing_name thing_color )];
}

sub sort_order {
    return ['thing_id' ] ;
}

sub delimiter { "\t" }

BEGIN {
    our $BASE_PATH = "/tmp/some_filemux_$$/";
    mkdir $BASE_PATH;
}

# Note that the file resolver is called as a normal function (with the parameters
# mentioned in requiret_for_get), not as a method with the data source as the
# first arg...
sub file_resolver {
    my $type = shift;
    our $BASE_PATH;
    return "$BASE_PATH/$type";
}

END { 
    our $BASE_PATH;
    my @files = glob("$BASE_PATH/*");
    unlink @files;
    rmdir $BASE_PATH;
}

1;
