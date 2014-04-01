use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;

use Test::More tests => 57;
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

    diag('sqlite file');
    my $db_file = load_objects_fill_file();
    test_results_db_file($db_file);

    diag('sqlite directory');
    my $db_dir = load_objects_fill_dir();
    test_results_db_dir($db_dir);
}

sub fill_primary_db {
    my $dbh = URT::DataSource::SomeSQLite->get_default_handle;

    $dbh->do('PRAGMA foreign_keys = ON');

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
    ok($dbh->do('create table obj (obj_id integer NOT NULL PRIMARY KEY, name varchar)'),
        'create table obj');
    ok($dbh->do('create table hangoff (hangoff_id integer NOT NULL PRIMARY KEY, value varchar, obj_id integer REFERENCES obj(obj_id))'),
        'create table hangoff');
    $sth = $dbh->prepare('insert into obj (obj_id, name) values (?,?)') || die "prepare obj: $DBI::errstr";
    foreach my $row ( [1, 'use'], [2, 'ignore'], [3, 'keep'] ) {
        $sth->execute(@$row) || die "execute hangoff: $DBI::errstr";
    }
    $sth->finish;

    $sth = $dbh->prepare('insert into hangoff (hangoff_id, value, obj_id) values (?,?,?)') || die "prepare hangoff: $DBI::errstr";
    foreach my $row ( [1, 'use', 1], [2, 'ignore', 2], [3, 'keep', 3] ) {
        $sth->execute(@$row) || die "execute obj: $DBI::errstr";
    }
    $sth->finish;


    # data and data_attribute tables
    ok($dbh->do('create table data (data_id integer NOT NULL PRIMARY KEY, name varchar)'),
        'create table data');
    ok($dbh->do('create table data_attribute (data_id integer, name varchar, value varchar, PRIMARY KEY (data_id, name, value))'),
        'create table data_attribute');
    $sth = $dbh->prepare('insert into data (data_id, name) values (?,?)') || die "prepare data: $DBI::errstr";
    foreach my $row ( [ 1, 'use'], [2, 'ignore'], [3, 'use'] ) {
        $sth->execute(@$row) || die "execute data: $DBI::errstr";
    }
    $sth->finish;

    $sth = $dbh->prepare('insert into data_attribute (data_id, name, value) values (?,?,?)') || die "prepare data_attribute: $DBI::errstr";
    # data_id 3 has no data_attributes
    foreach my $row ( [1, 'coolness', 'high'], [1, 'foo', 'bar'], [2, 'coolness', 'low']) {
        $sth->execute(@$row) || die "execute data_attribute: $DBI::errstr";
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
        class_name => 'URT::Obj',
        id_by => 'obj_id',
        has => [
            name => { is => 'String' },
            hangoff => { is => 'URT::Hangoff', reverse_as => 'obj', is_many => 1 },
            hangoff_value => { via => 'hangoff', to => 'value' },
        ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'obj',
    );

    UR::Object::Type->define(
        class_name => 'URT::Hangoff',
        id_by => 'hangoff_id',
        has => [
            value => { is => 'String' },
            obj => { is => 'URT::Obj', id_by => 'obj_id' },
        ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'hangoff',
    );


    UR::Object::Type->define(
        class_name => 'URT::Data',
        id_by => 'data_id',
        has => [
            name => { is => 'String' },
            attributes => { is => 'URT::DataAttribute', reverse_as => 'data', is_many => 1 },
        ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'data',
    );

    UR::Object::Type->define(
        class_name => 'URT::DataAttribute',
        id_by => ['data_id', 'name', 'value' ],
        has => [
            data => { is => 'URT::Data', id_by => 'data_id' },
        ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'data_attribute',
    );
}


sub load_objects_fill_file {
    my $temp_db_file = File::Temp->new();
    URT::DataSource::SomeSQLite->alternate_db_dsn('dbi:SQLite:dbname='.$temp_db_file->filename);
    _load_objects();
    URT::DataSource::SomeSQLite->alternate_db_dsn('');
    return $temp_db_file;
}

sub _load_objects {
    ok(scalar(URT::Simple->get(name => 'use')), 'Get simple object');

    ok(scalar(URT::Child->get(name => 'use')), 'Get child object');

    ok(scalar(URT::Obj->get(hangoff_value => 'use')), 'Get obj with hangoff');

    ok(scalar(URT::Hangoff->get(value => 'keep')), 'Get hangoff data directly');

    my @got = URT::Data->get(name => 'use', -hints => 'attributes');
    ok(scalar(@got), 'Get data and and data attributes');

    $_->unload() foreach ( qw( URT::Simple URT::Child URT::Obj URT::Hangoff URT::Data URT::DataAttribute ) );
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
        { 1 => { obj_id => 1, name => 'use' },
          3 => { obj_id => 3, name => 'keep' },
         },
        'table obj');

    my $hangoff = $dbh->selectall_hashref('select * from hangoff', 'hangoff_id');
    is_deeply($hangoff,
        {
          1 => { hangoff_id => 1, obj_id => 1, value => 'use' },
          3 => { hangoff_id => 3, obj_id => 3, value => 'keep'},
         },
        'table hangoff');

    my $data = $dbh->selectall_hashref('select * from data', 'data_id');
    is_deeply($data,
        { 1 => { data_id => 1, name => 'use' },
          3 => { data_id => 3, name => 'use' },
        },
        'table data');
$DB::single=1;

    my $data_attribute = $dbh->selectall_hashref('select * from data_attribute', 'name');
    is_deeply($data_attribute,
        { coolness  => { data_id => 1, name => 'coolness', value => 'high' },
          foo       => { data_id => 1, name => 'foo', value => 'bar' }
        },
        'table data_attribute'
    );
}

sub load_objects_fill_dir {
    my $temp_db_dir = File::Temp::tempdir( CLEANUP => 1 );
    URT::DataSource::SomeSQLite->alternate_db_dsn('dbi:SQLite:dbname='.$temp_db_dir);
    _load_objects();
    URT::DataSource::SomeSQLite->alternate_db_dsn('');
    return $temp_db_dir;
}

sub test_results_db_dir {
    my $temp_db_dir = shift;
    my $main_schema_file = File::Spec->catfile($temp_db_dir, 'main.sqlite3');
    ok(-f $main_schema_file, 'main schema file main.sqlite3');
    test_results_db_file($main_schema_file);
}
