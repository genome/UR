use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";

use URT;
use Test::More 'no_plan';

use URT::DataSource::SomeSQLite;

=cut
#This test verifies that sql generation is correct for inserts and deletes on tables with nullable foreign key constraints
#For a new object, an INSERT statement should be returned, with null values in nullable foreign key columns, and a corresponding UPDATE statement to set foreign key values after the insert
#For object deletion, an UPDATE statement setting nullable foreign keys to null is expected with the DELETE statement
=cut

END {
    unlink URT::DataSource::SomeSQLite->server;
}

setup_classes_and_db();

#test failure conditions

my @circular = URT::Circular->get(id => [1,2,3,4]);
ok (@circular, 'got objects from circular table');
isa_ok ($circular[0], 'URT::Circular');
is ( scalar @circular, 4, 'got expected number of objects from circular table');
for (@circular){
    $_->delete;
}

eval{
    UR::Context->commit();
};

sub setup_classes_and_db {
    my $dbh = URT::DataSource::SomeSQLite->get_default_dbh;

    ok($dbh, 'Got DB handle');

    ok( $dbh->do("create table circular (id integer, parent_id integer REFERENCES circular(id))"),
       'Created circular table');

    ok( $dbh->do("create table left (id integer, right_id integer REFERENCES right(id))"),
       'Created left table');

    ok( $dbh->do("create table right (id integer, left_id integer REFERENCES left(id))"),
       'Created right table');

    my $ins_circular = $dbh->prepare("insert into circular (id, parent_id) values (?,?)");
    foreach my $row (  [1, 5], [2, 1], [3, 2], [4, 3], [5, 4]  ) {
        ok( $ins_circular->execute(@$row), 'Inserted into circular' );
    }
    $ins_circular->finish;

    my $ins_left = $dbh->prepare("insert into left (id, right_id) values (?,?)");
    my $ins_right = $dbh->prepare("insert into right (id, left_id) values (?,?)");
    foreach my $row ( ( [1, 1], [2,2], [3,3], [4,4], [5,5]) ) {
        ok( $ins_left->execute(@$row), 'Inserted into left');
        ok( $ins_right->execute(@$row), 'Inserted into right');
    }
    $ins_left->finish;
    $ins_right->finish;

    ok($dbh->commit(), 'DB commit');
           
 
    ok(UR::Object::Type->define(
        class_name => 'URT::Circular',
        id_by => [
            id => { is => 'Integer' },
        ],
        has_optional => [
            parent_id => { is => 'Integer'},
            parent => {is => 'URT::Circular', id_by => 'parent_id'}
        ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'circular',
    ), 'Defined URT::Circular class');
    ok(UR::Object::Type->define(
        class_name => 'URT::Left',
        id_by => [
            id => { is => 'Integer'}
        ],
        has_optional => [
            right_id => { is => 'Integer' },
            right => { is => 'URT::Right', id_by => 'right_id'},
        ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'left',
    ), 'Defined URT::Left class');
    ok(UR::Object::Type->define(
        class_name => 'URT::Right',
        id_by => [
            id => { is => 'Integer'}
        ],
        has_optional => [
            left_id => { is => 'Integer' },
            left => { is => 'URT::Left', id_by => 'left_id'},
        ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'right',
    ), 'Defined URT::Right class');
}
