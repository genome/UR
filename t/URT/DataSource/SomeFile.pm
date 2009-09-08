package URT::DataSource::SomeFile;
use strict;
use warnings;

#use UR::Object::Type;
use URT;

our $FILE = "/tmp/ur_testsuite_db_$$.csv";
unlink $FILE if -e $FILE;

class URT::DataSource::SomeFile {
    is => ['UR::Singleton', 'UR::DataSource::File'],
    type_name => 'urt datasource somefile',
        
};

sub server { $FILE }

sub column_order {
    return [ qw( thing_id thing_name thing_color ) ];
}

sub sort_order {
    return ['thing_id'];
}

sub delimiter { "\t" }


1;
