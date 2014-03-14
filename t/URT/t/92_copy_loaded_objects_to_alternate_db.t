use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;

use Test::More tests => 39;
use URT::DataSource::SomeSQLite;
use File::Temp;
use File::Spec;

# Make a few couple classes attached to a data source.  Load some of the objects.
# The data should be copied to the test database

fill_primary_db();
setup_classes();

foreach my $no_commit ( 0, 1 ) {
    diag("no_commit $no_commit");
    UR::DBI->no_commit($no_commit);

    my $db_file = load_objects_fill_file();
    test_results_db_file($db_file);

    my $db_dir = load_objects_fill_dir();
    test_results_db_dir($db_dir);
}

sub fill_primary_db {
    my $dbh = URT::DataSource::SomeSQLite->get_default_handle;

    # "simple" is a basic table, no inheritance or hangoffs
    ok($dbh->do('create table simple (simple_id integer NOT NULL PRIMARY KEY, name varchar)'),
        'create table simple');
    my $sth = $dbh->prepare('insert into simple (simple_id, name) values (?,?)') || die "prepare simple: $DBI::errstr";
    foreach my $row ( [1, 'use'], [2, 'ignore'] ) {
        $sth->execute(@$row) || die "execute simple: $DBI::errstr";
    }
    $sth->finish;

    # "parent" and "child" tables with inheritance
    ok($dbh->do('create table parent (parent_id integer NOT NULL PRIMARY KEY, name varchar)'),
        'create table parent');
    ok($dbh->do('create table child (child_id integer NOT NULL PRIMARY KEY REFERENCES parent(parent_id), data varchar)'),
        'create table child');
    $sth = $dbh->prepare('insert into parent (parent_id, name) values (?,?)') || die "prepare parent: $DBI::errstr";
    foreach my $row ( [1, 'use'], [2, 'ignore']) {
        $sth->execute(@$row) || die "execute parent: $DBI::errstr";
    }
    $sth->finish;

    $sth = $dbh->prepare('insert into child (child_id, data) values (?,?)') || die "prepare child: $DBI::errstr";
    foreach my $row ( [1, 'child data 1'], [2, 'child data 2'] ) {
        $sth->execute(@$row) || die "execute child: $DBI::errstr";
    }
    $sth->finish;


    # "obj" and "hangoff" tables
    ok($dbh->do('create table hangoff (hangoff_id integer NOT NULL PRIMARY KEY, name varchar)'),
        'create table obj');
    ok($dbh->do('create table obj (obj_id integer NOT NULL PRIMARY KEY, hangoff_id integer NOT NULL REFERENCES hanhoff(hangoff_id), data varchar)'),
        'create table hangoff');
    $sth = $dbh->prepare('insert into hangoff (hangoff_id, name) values (?,?)') || die "prepare hangoff: $DBI::errstr";
    foreach my $row ( [1, 'use'], [2, 'ignore']) {
        $sth->execute(@$row) || die "execute obj: $DBI::errstr";
    }
    $sth->finish;

    $sth = $dbh->prepare('insert into obj (obj_id, hangoff_id) values (?,?)') || die "prepare obj: $DBI::errstr";
    foreach my $row ( [1, 1], [2, 2] ) {
        $sth->execute(@$row) || die "execute hangoff: $DBI::errstr";
    }
    $sth->finish;
}

sub setup_classes {
    UR::Object::Type->define(
        class_name => 'URT::Simple',
        id_by => 'simple_id',
        has => ['name'],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'simple',
    );

    UR::Object::Type->define(
        class_name => 'URT::Parent',
        id_by => 'parent_id',
        has => ['name'],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'parent',
    );

    UR::Object::Type->define(
        class_name => 'URT::Child',
        is => 'URT::Parent',
        id_by => 'child_id',
        has => ['data'],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'child',
    );

    UR::Object::Type->define(
        class_name => 'URT::Hangoff',
        id_by => 'hangoff_id',
        has => ['name'],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'hangoff',
    );

    UR::Object::Type->define(
        class_name => 'URT::Obj',
        id_by => 'obj_id',
        has => [
            hangoff => { is => 'URT::Hangoff', id_by => 'hangoff_id' },
            hangoff_name => { via => 'hangoff', to => 'name' },
        ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'obj',
    );
}


sub load_objects_fill_file {
    my $temp_db_file = File::Temp->new();
    local $ENV{UR_TEST_FILLDB} = 'dbi:SQLite:dbname='.$temp_db_file->filename;
    _load_objects();
    return $temp_db_file;
}

sub _load_objects {
    ok(scalar(URT::Simple->get(name => 'use')), 'Get simple object');

    ok(scalar(URT::Child->get(name => 'use')), 'Get child object');

    ok(scalar(URT::Obj->get(hangoff_name => 'use')), 'Get obj with hangoff');

    $_->unload() foreach ( qw( URT::Simple URT::Child URT::Obj URT::Hangoff ) );
}

sub test_results_db_file {
    my $db_file = shift;

    my $dbh = DBI->connect("dbi:SQLite:dbname=$db_file",'','');
    $dbh->{FetchHashKeyName} = 'NAME_lc';

    my $simple = $dbh->selectall_hashref('select * from simple', 'simple_id');
    is_deeply($simple,
                { 1 => { simple_id => 1, name => 'use' } },
                'simple table created with correct column names');

    my $parent = $dbh->selectall_hashref('select * from parent', 'parent_id');
    is_deeply($parent,
        { 1 => { parent_id => 1, name => 'use' } },
        'table parent');

    my $child = $dbh->selectall_hashref('select * from child', 'child_id');
    is_deeply($child,
        { 1 => { child_id => 1, data => 'child data 1' } },
        'table child');

    my $obj = $dbh->selectall_hashref('select * from obj', 'obj_id');
    is_deeply($obj,
        { 1 => { obj_id => 1, hangoff_id => 1 } },
        'table obj');

    my $hangoff = $dbh->selectall_hashref('select * from hangoff', 'hangoff_id');
    is_deeply($hangoff,
        { 1 => { hangoff_id => 1, name => 'use' } },
        'table hangoff');
}

sub load_objects_fill_dir {
    my $temp_db_dir = File::Temp::tempdir( CLEANUP => 1 );
    local $ENV{UR_TEST_FILLDB} = 'dbi:SQLite:dbname='.$temp_db_dir;
    _load_objects();
    return $temp_db_dir;
}

sub test_results_db_dir {
    my $temp_db_dir = shift;
    my $main_schema_file = File::Spec->catfile($temp_db_dir, 'main.sqlite3');
    ok(-f $main_schema_file, 'main schema file main.sqlite3');
    test_results_db_file($main_schema_file);
}
