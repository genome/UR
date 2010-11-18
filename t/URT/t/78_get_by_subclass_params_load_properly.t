use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use above 'UR';
use above 'URT';

use Test::More tests => 14;
use URT::DataSource::SomeSQLite;

# This tests a get() by subclass specific parameters on a subclass with no table of its own.
# The subclass specific parameters are stored in a hangoff table (animal_param in this case).
# There was a bug causing the queries to be improperly cached. Specifically, querying by
# subclass specific parameters caused the cache to believe it had loaded all objects of that
# specific subclass.

setup_classes_and_db();

my $fido = URT::Dog->get(color => 'black');
ok($fido, 'got fido');
is($fido->name, 'fido', 'fido has correct name');
is($fido->id, 1, 'fido has correct id');

my $rex = URT::Dog->get(color => 'brown');
ok($rex, 'got rex');
is($rex->name, 'rex', 'rex has correct name');
is($rex->id, 2, 'rex has correct id');

done_testing();

sub setup_classes_and_db {
    my $dbh = URT::DataSource::SomeSQLite->get_default_dbh;

    ok($dbh, 'Got DB handle');

    ok($dbh->do(q{
            create table animal (
                animal_id   integer,
                name        varchar,
                subclass    varchar)}),
        'Created animal table');

    ok($dbh->do(q{
            create table animal_param (
                animal_param_id integer,
                animal_id       integer references animal(animal_id),
                param_name      varchar,
                param_value     varchar)}),
        'Created animal_param table');

    ok($dbh->do("insert into animal (animal_id, name, subclass) values (1,'fido','URT::Dog')"),
        'inserted dog 1');
    ok($dbh->do("insert into animal_param (animal_param_id, animal_id, param_name, param_value) values (1, 1, 'color', 'black')"),
        'turned fido black');

    ok($dbh->do("insert into animal (animal_id, name, subclass) values (2,'rex','URT::Dog')"),
        'inserted dog 2');
    ok($dbh->do("insert into animal_param (animal_param_id, animal_id, param_name, param_value) values (2, 2, 'color', 'brown')"),
        'turned rex brown');
   
    ok($dbh->commit(), 'DB commit');
           
    UR::Object::Type->define(
        class_name => 'URT::Animal',
        id_by => [
            animal_id => { is => 'NUMBER', len => 10 },
        ],
        has => [
            name => { is => 'Text' },
            subclass => { is => 'Text' },
        ],
        has_many_optional => [
            params => { is => 'URT::AnimalParam', reverse_as => 'animal', },
        ],
        is_abstract => 1,
        subclassify_by => 'subclass',
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'animal',
    ); 

    UR::Object::Type->define(
        class_name => 'URT::Dog',
        is => 'URT::Animal',
        id_by => [
            dog_id => { is => 'NUMBER' },
        ],
        has => [
            color => { 
                via => 'params',
                is => 'Text',
                to => 'param_value',
                where => [ param_name => 'color', ],
            },
        ],
    );

    sub URT::Dog::create() {
        print "KREATE!\n";
    }

    UR::Object::Type->define(
        class_name => 'URT::AnimalParam',
        id_by => [
            animal_param_id => { is => 'NUMBER' },
        ],
        has => [
            animal => { id_by => 'animal_id', is => 'URT::Animal' },
            param_name => { is => 'Text' },
            param_value => { is => 'Text' },
        ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'animal_param',
    );
}

