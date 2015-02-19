use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;

use Test::More tests => 6;
use URT::DataSource::SomeSQLite;

my $dbh = URT::DataSource::SomeSQLite->get_default_handle;
ok($dbh, 'Got DB handle');

my $existing_obj_id = 99;
&setup_classes_and_db();

my($created_obj_id, $created_obj_name);
subtest create => sub {
    plan tests => 6;

    my $external_obj = URT::NamedThing->create(name => 'external');
    ok($external_obj, 'Create object outside transaction');

    my $trans = UR::Context::SyncableTransaction->begin();
    ok($trans, 'begin syncable transaction');

    my $internal_obj = URT::NamedThing->create(name => 'created');
    ok($internal_obj, 'Create object in transaction');
    ($created_obj_id, $created_obj_name) = ($internal_obj->id, $internal_obj->name);

    ok($trans->commit(), 'commit() transaction');

    my $row = get_row_from_db_with_id($internal_obj->id);
    is_deeply($row,
              [ $internal_obj->id, $internal_obj->name],
              'Object was saved to DB');

    $row = get_row_from_db_with_id($external_obj->id);
    ok(! $row, 'Object external to transaction was not saved');
};

subtest delete => sub {
    plan tests => 5;

    ok(get_row_from_db_with_id($existing_obj_id), 'Object exists in db');

    my $trans = UR::Context::SyncableTransaction->begin();
    ok($trans, 'begin syncable transaction');

    my $obj = URT::NamedThing->get($existing_obj_id);
    ok($obj->delete, 'delete object');

    ok($trans->commit(), 'commit transaction');
    ok(! get_row_from_db_with_id($existing_obj_id), 'Object is deleted');
};

subtest change => sub {
    plan tests => 6;

    is_deeply(get_row_from_db_with_id($created_obj_id),
            [ $created_obj_id, $created_obj_name ],
            'Object previously created and saved is still in DB');
    ok(my $obj = URT::NamedThing->get($created_obj_id), 'Got object previously created and saved');

    my $trans = UR::Context::SyncableTransaction->begin();
    ok($trans, 'begin syncable transaction');

    my $altered_name = $created_obj_name . '_foo';
    ok($obj->name($altered_name), 'Change name');

    ok($trans->commit(), 'Commit transaction');

    is_deeply(get_row_from_db_with_id($created_obj_id),
            [ $created_obj_id, $altered_name ],
            'Name is changed in DB');
};


sub get_row_from_db_with_id {
    my $id = shift;
    my $sth = $dbh->prepare('select * from named_thing where named_thing_id = ?');
    $sth->execute($id);
    my $row = $sth->fetchrow_arrayref();
    return $row;
}
    

sub setup_classes_and_db {
    ok( $dbh->do("create table named_thing (named_thing_id integer PRIMARY KEY, name varchar NOT NULL)"),
        'Created named_thing table');

    $dbh->do("insert into named_thing values($existing_obj_id, 'bob')");
    ok($dbh->commit(), 'DB commit');

    UR::Object::Type->define(
        class_name => 'URT::NamedThing',
        id_by => [
            named_thing_id => { is => 'Integer' },
        ],
        has => [
            name => { is => 'String' },
        ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'named_thing',
    );
}
