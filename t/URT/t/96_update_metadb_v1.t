use strict;
use warnings;
use Test::More tests=> 52;
use File::Temp;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

# Test getting some objects that includes -hints, and then that later get()s
# don't re-query the DB

use URT;

# For the sqlite metadb, we just want File::Temp to clean up after we're done
my $meta_fh = File::Temp->new(SUFFIX => '.sqlite3');
my $meta_pathname = $meta_fh->filename;
close($meta_fh);
unlink($meta_pathname);

my $meta_3n_pathname = $meta_pathname . 'n';
IO::File->new($meta_3n_pathname, 'w')->close();

# For the dump file, we'll fill in the text.
my $meta_dump_fh = File::Temp->new(SUFFIX => '.sqlite3-dump');
my $meta_dump_pathname = $meta_dump_fh->filename;
&write_metadb_dump($meta_dump_fh);
close($meta_dump_fh);

ok(! -f $meta_pathname, 'MetaDB correctly does not exist yet');
ok(-f $meta_dump_pathname, 'MetaDB dump exists');

my $test_metadb = UR::Object::Type->define(
    class_name => 'URT::DataSource::TestMeta',
    is => ['UR::DataSource::Meta'],
    has_constant_classwide => [
        server          => { value => $meta_pathname },
        _data_dump_path => { value => $meta_dump_pathname },
    ],
);

ok($test_metadb, 'Defined TestMeta datasource');

my $dbh;
$dbh = eval { URT::DataSource::TestMeta->get_default_handle; };
ok(!$dbh, 'Correctly could not get DB handle initially');
like($@,qr/The MetaDB.*has extension \.sqlite3n/, 'The exception was correct');
unlink($meta_3n_pathname);


my $update_cmd = UR::Namespace::Command::Update::MetaDbSchema->create(data_source_name => 'URT::DataSource::TestMeta');
ok($update_cmd, 'Created command obj to update metadb');
$update_cmd->dump_status_messages(0);
$update_cmd->dump_warning_messages(0);
$update_cmd->dump_error_messages(0);
$update_cmd->queue_status_messages(1);
$update_cmd->queue_warning_messages(1);
$update_cmd->queue_error_messages(1);

ok($update_cmd->execute(),'Execute update metadb command');


ok(-f $meta_pathname,'MetaDB now exists');
ok(-f $meta_dump_pathname, 'MetaDB dump still exists');

my @table_names = sort URT::DataSource::TestMeta->_get_table_names_from_data_dictionary();
is_deeply(\@table_names,
          [qw(dd_bitmap_index dd_fk_constraint dd_fk_constraint_column dd_meta_settings
              dd_pk_constraint_column dd_table dd_table_column dd_unique_constraint_column) ],
         'All expected tables are there');

$dbh = URT::DataSource::TestMeta->get_default_handle();
ok($dbh, 'Got handle for MetaDB');

foreach my $meta_table_name ( qw(dd_bitmap_index dd_fk_constraint dd_fk_constraint_column 
                                 dd_pk_constraint_column dd_table dd_table_column dd_unique_constraint_column) )
{
    my $sth = $dbh->prepare("select * from $meta_table_name");
    ok($sth, "got sth for getting data from meta db table $meta_table_name");
    ok($sth->execute(), 'execute sth');
    my $numrows = 0;
    while (my $row = $sth->fetchrow_hashref) {
        $numrows++;
        if (exists $row->{'owner'}) {
            if ($row->{'table_name'} eq 'SomeTable') {
                is($row->{'owner'}, 'main', "'owner' metadata updated for table $meta_table_name to 'main'");
            } elsif ($row->{'table_name'} eq 'SomeOtherTable') {
                is($row->{'owner'}, 'notmain', "'owner' metadata not touched where is was 'notmain'");
            } else  {
                ok(0, "'table_name' had unexpected data in meta table $meta_table_name: ".$row->{'owner'});
            }
        }
        if (exists $row->{'r_owner'}) {
            if ($row->{'table_name'} eq 'SomeTable') {
                is($row->{'r_owner'}, 'main', "'r_owner' metadata updated for table $meta_table_name to 'main'");
            } elsif ($row->{'table_name'} eq 'SomeOtherTable') {
                is($row->{'r_owner'}, 'notmain', "'r_owner' metadata not touched where is was 'notmain'");
            } else {
              ok(0, "'table_name' had unexpected data in meta table $meta_table_name: ".$row->{'owner'});
            }
        }
    }
    is($numrows, 2, "Read 2 rows for metadata table $meta_table_name");
}

my $sth = $dbh->prepare('select * from dd_meta_settings');
ok($sth, 'Create sth to get data from dd_meta_settings');
ok($sth->execute(), 'Execute sth');
my $numrows = 0;
while (my $row = $sth->fetchrow_hashref) {
    $numrows++;
    if ($row->{'key'} eq 'ur_metadb_version') {
        is($row->{'value'}, URT::DataSource::TestMeta->CURRENT_METADB_VERSION, 'ur_metadb_version has the correct value');
    }
}
is($numrows, 1, 'There was 1 row in the dd_meta_settings table');
    





sub write_metadb_dump {
    my $meta_fh = shift;

    # Fill in a version 0 metadb dump.  This is cut-and-pasted from UR::DataSource::Meta
    my $METADATA_DB_SQL =<<EOS;
CREATE TABLE IF NOT EXISTS dd_bitmap_index (
    data_source varchar NOT NULL,
    owner varchar,
    table_name varchar NOT NULL,
    bitmap_index_name varchar NOT NULL,
    PRIMARY KEY (data_source, owner, table_name, bitmap_index_name)
);
INSERT INTO dd_bitmap_index VALUES ('Some::DataSource',NULL,'SomeTable','TheBitmapIndex');
INSERT INTO dd_bitmap_index VALUES ('Some::DataSource','notmain','SomeOtherTable','TheBitmapIndex');
CREATE TABLE IF NOT EXISTS dd_fk_constraint (
    data_source varchar NOT NULL,
    owner varchar,
    r_owner varchar,
    table_name varchar NOT NULL,
    r_table_name varchar NOT NULL,
    fk_constraint_name varchar NOT NULL,
    last_object_revision timestamp NOT NULL,
    PRIMARY KEY(data_source, owner, r_owner, table_name, r_table_name, fk_constraint_name)
);
INSERT INTO dd_fk_constraint VALUES ('Some::Data::Source', NULL, NULL, 'SomeTable', 'SomeOtherTable', 'TheFkConstraint', 1234);
INSERT INTO dd_fk_constraint VALUES ('Some::Data::Source', 'notmain', 'notmain', 'SomeOtherTable', 'SomeThirdTable', 'TheFkConstraint', 1234);
CREATE TABLE IF NOT EXISTS dd_fk_constraint_column (
    fk_constraint_name varchar NOT NULL,
    data_source varchar NOT NULL,
    owner varchar,
    table_name varchar NOT NULL,
    r_table_name varchar NOT NULL,
    column_name varchar NOT NULL,
    r_column_name varchar NOT NULL,

    PRIMARY KEY(data_source, owner, table_name, fk_constraint_name, column_name)
);
INSERT INTO dd_fk_constraint_column VALUES ('TheFkConstraint','Some::Data::Source',NULL,'SomeTable', 'SomeOtherTable','col1','col2');
INSERT INTO dd_fk_constraint_column VALUES ('TheFkConstraint','Some::Data::Source','notmain','SomeOtherTable', 'SomeThirdTable','col1','col2');
CREATE TABLE IF NOT EXISTS dd_pk_constraint_column (
    data_source varchar NOT NULL,
    owner varchar,
    table_name varchar NOT NULL,
    column_name varchar NOT NULL,
    rank integer NOT NULL,
    PRIMARY KEY (data_source,owner,table_name,column_name,rank)
);
INSERT INTO dd_pk_constraint_column VALUES ('Some::Data::Source', NULL,'SomeTable','col1', 0);
INSERT INTO dd_pk_constraint_column VALUES ('Some::Data::Source', 'notmain','SomeOtherTable','col1', 0);
CREATE TABLE IF NOT EXISTS dd_table (
     data_source varchar NOT NULL,
     owner varchar,
     table_name varchar NOT NULL,
     table_type varchar NOT NULL,
     er_type varchar NOT NULL,
     last_ddl_time timestamp,
     last_object_revision timestamp NOT NULL,
     remarks varchar,
     PRIMARY KEY(data_source, owner, table_name)
);
INSERT INTO dd_table VALUES ('Some::Data::Source',NULL,'SomeTable','table','entity',1234,1234,'blahblah');
INSERT INTO dd_table VALUES ('Some::Data::Source','notmain','SomeOtherTable','table','entity',1234,1234,'blahblah');
CREATE TABLE IF NOT EXISTS dd_table_column (
    data_source varchar NOT NULL,
    owner varchar,
    table_name varchar NOT NULL,
    column_name varchar NOT NULL,
    data_type varchar NOT NULL,
    data_length varchar,
    nullable varchar NOT NULL,
    last_object_revision timestamp NOT NULL,
    remarks varchar,
    PRIMARY KEY(data_source, owner, table_name, column_name)
);
INSERT INTO dd_table_column VALUES ('Some::Data::Source',NULL,'SomeTable','col1','integer',1234,0,1234,'blahblah');
INSERT INTO dd_table_column VALUES ('Some::Data::Source','notmain','SomeOtherTable','col1','integer',1234,0,1234,'blahblah');
CREATE TABLE IF NOT EXISTS dd_unique_constraint_column (
    data_source varchar NOT NULL,
    owner varchar,
    table_name varchar NOT NULL,
    constraint_name varchar NOT NULL,
    column_name varchar NOT NULL,
    PRIMARY KEY (data_source,owner,table_name,constraint_name,column_name)
);
INSERT INTO dd_unique_constraint_column VALUES ('Some::Data::Source',NULL,'SomeTable','TheUkConstraint','col1');
INSERT INTO dd_unique_constraint_column VALUES ('Some::Data::Source','notmain','SomeOtherTable','TheUkConstraint','col1');
EOS

    $meta_fh->print($METADATA_DB_SQL);
}
   

