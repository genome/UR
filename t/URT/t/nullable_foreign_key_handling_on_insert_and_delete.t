use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";
use lib File::Basename::dirname(__FILE__)."/../../../lib/";

use URT;
use Test::More 'no_plan';

use URT::DataSource::SomeSQLite;
use Data::Dumper;

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
    my $id = $_->id;
    ok($_->delete, 'deleted object');
    my $ghost = URT::Circular::Ghost->get(id=> $id);
    my $ds = UR::Context->resolve_data_source_for_object($ghost);
    my @sql = $ds->_default_save_sql_for_object($ghost);
    #print Dumper [$ghost, $ds, \@sql];
}

eval{
    print "committing...\n";
    UR::Context->commit();
};

ok(!$@, "no error message for sqlite commit due to fk constraints not being enforced: $@");

my @bridges = URT::Bridge->get();
for (@bridges){
    ok($_->delete(), 'deleted bridge');
}

eval{
    UR::Context->commit();
};

ok( $@ =~ "Modifying nullable foreign key column LEFT_ID not allowed because it is a primary key column in BRIDGE", 'got expected error removing bridge table entries w/ nullable foreign key constraints that are part of primary key');

exit;

my @chain = (URT::Alpha->get(), URT::Beta->get(), URT::Gamma->get());

ok (@chain, 'got objects from alpha, beta, and gamma tables');
is (scalar @chain, 3, 'got expected number of objects');
for (@chain){
    ok($_->delete, 'deleted object');
}

eval{
    UR::Context->commit();
};

ok(!$@, "no error message on commit: $@");

my ($new_alpha, $new_beta, $new_gamma);

ok($new_alpha = URT::Alpha->create(id => 101, beta_id => 201), 'created new alpha');
ok($new_beta = URT::Beta->create(id => 201, gamma_id => 301), 'created new beta');
ok($new_gamma = URT::Gamma->create(id => 301, type => 'test2'), 'created new gamma');

eval {
    UR::Context->commit();
};

ok(!$@, "no error message on commit of new alpha,beta,gamma, would fail due to fk constraints if we weren't using sqlite datasource");


sub setup_classes_and_db {
    my $dbh = URT::DataSource::SomeSQLite->get_default_dbh;

    ok($dbh, 'Got DB handle');

    ok( $dbh->do("create table circular (id integer primary key, parent_id integer REFERENCES circular(id))"),

       'Created circular table');

    ok( $dbh->do("create table left (id integer primary key, right_id integer REFERENCES right(id))"),
       'Created left table');

    ok( $dbh->do("create table right (id integer primary key, left_id integer REFERENCES left(id))"),
       'Created right table');

    ok( $dbh->do("create table alpha (id integer primary key, beta_id integer REFERENCES beta(id))"),
        'Created table alpha');
    ok( $dbh->do("create table beta (id integer primary key, gamma_id integer REFERENCES gamma(id))"),
        'Created table beta');
    ok( $dbh->do("create table gamma (id integer primary key, type varchar)"),
        'Created table gamma');
    ok( $dbh->do("create table bridge (left_id integer REFERENCES left(id), right_id integer REFERENCES right(id), primary key (left_id,  right_id))"),
        'Created table bridge');


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
    
    
    my $ins_bridge_left = $dbh->prepare("insert into left(id) values (?)");
    $ins_bridge_left->execute(10);
    my $ins_bridge_right = $dbh->prepare("insert into right(id) values (?)");
    my $ins_bridge = $dbh->prepare("insert into bridge(left_id, right_id) values (?, ?)");
    for (11..15){
        $ins_bridge_right->execute($_);
        $ins_bridge->execute(10, $_);
    }
    $ins_bridge->finish;
    $ins_bridge_right->finish;
    $ins_bridge_left->finish;
    
    $ins_left->finish;
    $ins_right->finish;
    my $ins_alpha = $dbh->prepare("insert into alpha(id, beta_id) values(?,?)");
    $ins_alpha->finish;
    my $ins_beta = $dbh->prepare("insert into beta(id, gamma_id) values(?,?)");
    ok($ins_beta->execute(200, 300), 'inserted into beta');
    $ins_beta->finish;
    my $ins_gamma = $dbh->prepare("insert into gamma(id, type) values(?,?)");
    ok($ins_gamma->execute(300, 'test'), 'inserted into gamma');
    $ins_gamma->finish;


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
    ok(UR::Object::Type->define(
            class_name => 'URT::Alpha',
            id_by => [
                id => {is => 'Integer'}
            ],
            has_optional => [
                beta_id => { is => 'Integer' }, 
                beta => { is => 'URT::Beta', id_by => 'beta_id'},
            ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'alpha',
    ), 'Defined URT::Alpha class');
    ok(UR::Object::Type->define(
            class_name => 'URT::Beta',
            id_by => [
                id => {is => 'Integer'}
            ],
            has_optional => [
                gamma_id => { is => 'Integer' }, 
                gamma => { is => 'URT::Gamma', id_by => 'gamma_id'},
            ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'beta',
    ), 'Defined URT::Beta class');
    ok(UR::Object::Type->define(
            class_name => 'URT::Gamma',
            id_by => [
                id => {is => 'Integer'}
            ],
            has => [
                type => { is => 'Text' }, 
            ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'gamma',
    ), 'Defined URT::Alpha class');
    ok(UR::Object::Type->define(
            class_name => 'URT::Bridge',
            id_by => [
                left_id => {is => 'Integer'},
                right_id => {is => 'Integer'}
            ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'bridge',
    ), 'Defined URT::Bridge class');
}
