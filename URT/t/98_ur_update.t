#!/usr/bin/env perl

use strict;
use warnings;

#BEGIN { $ENV{UR_CONTEXT_BASE} = "URT::Context::Testing" };

use URT;
use DBI;
use IO::Pipe;
use Test::More tests => 76;
use UR::Command::Update::Classes;
UR::DBI->no_commit(1);

# This can only be run with the cwd at the top of the URT namespace

require Cwd;
my $working_dir = Cwd::abs_path();
if ($working_dir !~ m/\/URT/) {
    my($urt_dir) = ($INC{'URT.pm'} =~ m/^(.*)\.pm$/);
    if (-d $urt_dir) {
        chdir($urt_dir);
    } else {
        die "Cannot determine URT's namespace directory, exiting";
    }
}


# Make a fresh sqlite database in tmp.

my $ds_class = 'URT::DataSource::SomeSQLite';
my $sqlite_file = $ds_class->server;

cleanup_files();

sub cleanup_files {
    unlink $sqlite_file;

    for my $filename (
        qw|
            Car.pm
            Employee.pm
            Person.pm
            .deleted/Car.pm
            .deleted/Employee.pm
            .deleted/Person.pm
        |
    ) {
        if (-e $filename) {
            #warn "unlinking $filename\n";
            unlink $filename;
        }
    }
}

UR::Command::Update::Classes->dump_error_messages(1);
UR::Command::Update::Classes->dump_warning_messages(1);
UR::Command::Update::Classes->dump_status_messages(0);
UR::Command::Update::Classes->status_messages_callback(
    sub {
        my $self = shift;
        my $msg = shift;
        print "   $msg\n";
        return 1;
    }
);

# This command will be used below multiple times.

my($delegate_class,$create_params) = UR::Command::Update::Classes->resolve_class_and_params_for_argv(qw(--data-source URT::DataSource::SomeSQLite));
ok($delegate_class, "Resolving parameters for update: class is $delegate_class");

my $command_obj = $delegate_class->create(%$create_params, _override_no_commit_for_filesystem_items => 1);
ok($command_obj, "Created a command object for updating the classes");

my $dbh = $ds_class->get_default_dbh();
ok($dbh, 'Got database handle');

# This wrapper to get_changes filters out things like the command-line parameters
# until that bug is fixed.

my $trans;
sub get_changes {
    my @changes =
        grep { $_->changed_class_name ne "UR::Command::Param" }
        grep { $_->changed_class_name ne 'UR::DataSource::Meta' && substr($_->changed_aspect,0,1) ne '_'}
        $trans->get_change_summary();
    return @changes;
}

sub cached_dd_objects {
    my @obj =
        grep { ref($_) =~ /::DB::/ }
        UR::Object->all_objects_loaded, UR::Object::Ghost->all_objects_loaded;
}

sub cached_dd_object_count {
    my @obj =
        grep { ref($_) =~ /::DB::/ }
        UR::Object->all_objects_loaded, UR::Object::Ghost->all_objects_loaded;
    return scalar(@obj);
}

sub cached_class_object_count {
    my @obj =
        grep { ref($_) =~ /UR::Object::/ }
        UR::Object->all_objects_loaded, UR::Object::Ghost->all_objects_loaded;
    return scalar(@obj);
}

sub cached_person_dd_objects {
    my @obj =
        grep { $_->{table_name} eq "person" }
        grep { ref($_) =~ /::DB::/ }
        UR::Object->all_objects_loaded, UR::Object::Ghost->all_objects_loaded;
}

sub cached_person_summary {
    my @obj = map { ref($_) . "\t" . $_->{id} } cached_person_dd_objects();
    return @obj;
}

sub undo_log_summary {
    my @c = do { no warnings; reverse @UR::Context::Transaction::change_log; };
    return
        map { $_->{changed_class_name} . "\t" . $_->{changed_id} . "\t" . $_->{changed_aspect} }
        grep { not ($_->{changed_class_name} =~ /^UR::Object/ and $_->{changed_aspect} eq "load") }
        @c;
}


# Empty schema

$trans = UR::Context::Transaction->begin();
ok($trans, "began transaction");

print Data::Dumper::Dumper($UR::Object::all_objects_loaded->{'UR::DataSource::RDBMS::Table::Ghost'});

    ok($command_obj->execute(),'Executing update on an empty schema');

    my @changes = get_changes();
    is(scalar(@changes),0, "no changes for an empty schema");

    # note this for comparison in future tests.
    my $expected_dd_object_count = cached_dd_object_count();

    # don't rollback

# Make a table

ok($dbh->do('CREATE TABLE person (person_id integer NOT NULL PRIMARY KEY, name varchar)'), 'Create person table');
$trans = UR::Context::Transaction->begin();
ok($trans, "CREATED PERSON and began transaction");

        ok($command_obj->execute(),'Executing update after creating person table');
        @changes = get_changes();
        # FIXME The test should probably break out each type of changed thing and check
        # that the counts of each type are correct, and not just the count of all changes
        is(scalar(@changes), 11, "found changes for the new table and class");

        my $personclass = UR::Object::Type->get('URT::Person');
        isa_ok($personclass, 'UR::Object::Type');  # FIXME why isn't this a UR::Object::Type
        ok($personclass->module_source_lines, 'Person class module has at least one line');
        is($personclass->type_name, 'person', 'Person class type_name is correct');
        is($personclass->class_name, 'URT::Person', 'Person class class_name is correct');
        is($personclass->table_name, 'PERSON', 'Person class table_name is correct');
        is($UR::Context::current->resolve_data_sources_for_class_meta_and_rule($personclass), $ds_class, 'Person class data_source is correct');
        is_deeply([sort $personclass->column_names],
                ['NAME','PERSON_ID'],
                'Person object has all the right columns');
        is_deeply([$personclass->id_column_names],
                ['PERSON_ID'],
                'Person object has all the right id column names');

        # Another test case should make sure the other class introspection methods like inherited_property_names,
        # all_table_names, etc work correctly for all kinds of objects

        my $module_path = $personclass->module_path;
        ok($module_path, "got a module path");
        ok(-f $module_path, 'Person.pm module exists');

        ok(! UR::Object::Type->get('URT::NonExistantClass'), 'Correctly cannot load a non-existant class');

        $DB::single = 1;
        $trans->rollback;
        ok($trans->isa("UR::DeletedRef"), "rolled-back transaction");
        is(cached_dd_object_count(), $expected_dd_object_count, "no data dictionary objects cached after rollback");

# Make the employee and car tables refer to person, and add a column to person

ok($dbh->do('CREATE TABLE employee (employee_id integer NOT NULL PRIMARY KEY CONSTRAINT fk_person_id REFERENCES person(person_id), rank integer)'), 'Employee inherits from Person');
ok($dbh->do('ALTER TABLE person ADD COLUMN postal_address varchar'), 'Add column to Person');
ok($dbh->do('CREATE TABLE car (car_id integer NOT NULL PRIMARY KEY, owner_id integer NOT NULL CONSTRAINT fk_person_id2 REFERENCES person(person_id), make varchar, model varchar, color varchar, cost number)'), 'Create car table');

#print join("\n",sort map { values %$_ } values %$UR::Context::all_objects_loaded);

$trans = UR::Context::Transaction->begin();
ok($trans, "CREATED EMPLOYEE AND CAR AND UPDATED PERSON and began transaction");

    ok($command_obj->execute(), 'Updating schema');
    @changes = get_changes();
    is(scalar(@changes), 47, "found changes for two new tables, and one modified table");

    # Verify the Person.pm and Employee.pm modules exist

    $personclass = UR::Object::Type->get('URT::Person');
    ok($personclass, 'Person class loaded');
    is_deeply([sort $personclass->column_names],
            ['NAME','PERSON_ID','POSTAL_ADDRESS'],
            'Person object has all the right columns');
    is_deeply([sort $personclass->class_name->property_names],
            ['name','person_id','postal_address'],
            'Person object has all the right properties');
    is_deeply([$personclass->id_column_names],
            ['PERSON_ID'],
            'Person object has all the right id column names');

    my $employeeclass = UR::Object::Type->get('URT::Employee');
    ok($employeeclass, 'Employee class loaded');
    isa_ok($employeeclass, 'UR::Object::Type');

    # There is no standardized way to spot inheritance from the shema.
    # The developer can reclassify in the source, and subsequent updates would respect it.
    # FIXME: test for this.

    ok(! $employeeclass->isa('URT::Car'), 'Employee class is correctly not a Car');
    ok($employeeclass->module_source_lines, 'Employee class module has at least one line');

    is_deeply([sort $employeeclass->column_names],
            ['EMPLOYEE_ID','RANK'],
            'Employee object has all the right columns');
    is_deeply([sort $employeeclass->class_name->property_names],
            ['employee_id','rank'],
            'Employee object has all the right properties');
    is_deeply([$employeeclass->id_column_names],
             ['EMPLOYEE_ID'],
            'Employee object has all the right id column names');
    ok($employeeclass->table_name eq 'EMPLOYEE', 'URT::Employee object comes from the employee table');


    my $carclass = UR::Object::Type->get('URT::Car');
    ok($carclass, 'Car class loaded');
    is($carclass->class_name,'URT::Car', "class name is set correctly");
    isa_ok($carclass,'UR::Object::Type');
    ok(! $carclass->class_name->isa('URT::Person'), 'Car class is correctly not a Person');

    is_deeply([sort $carclass->column_names],
            ['CAR_ID','COLOR','COST','MAKE','MODEL','OWNER_ID'],
            'Car object has all the right columns');
    # Is owner a property through owner_id?
    is_deeply([sort $carclass->class_name->property_names],
            ['car_id','color','cost','make','model','owner_id'],
            'Car object has all the right properties');
    is_deeply([$carclass->id_column_names],
            ['CAR_ID'],
            'Car object has all the right id column names');
        ok($carclass->table_name eq 'CAR', 'Car object comes from the car table');

    $trans->rollback;
    ok($trans->isa("UR::DeletedRef"), "rolled-back transaction");
    is(cached_dd_object_count(), $expected_dd_object_count, "no data dictionary objects cached after rollback");

# Drop a table

ok($dbh->do('DROP TABLE car'),'Removed Car table');
$trans = UR::Context::Transaction->begin();
ok($trans, "DROPPED CAR and began transaction");

    ok($command_obj->execute(), 'Updating schema');
    @changes = get_changes();
    is(scalar(@changes), 33, "found changes for one dropped table");

    ok($personclass = UR::Object::Type->get('URT::Person'),'Loaded Person class');
    ok($employeeclass = UR::Object::Type->get('URT::Employee'), 'Loaded Employee class');

    $carclass = UR::Object::Type->get('URT::Car');
    ok(!$carclass, 'Car class is correctly not loaded');

    $trans->rollback;
    ok($trans->isa("UR::DeletedRef"), "rolled-back transaction");
    is(cached_dd_object_count(), $expected_dd_object_count, "no data dictionary objects cached after rollback");

# Drop the other two tables

ok($dbh->do('DROP TABLE employee'),'Removed employee table');
ok($dbh->do('DROP TABLE person'),'Removed person table');
ok($dbh->do('CREATE TABLE person (person_id integer NOT NULL PRIMARY KEY, postal_address varchar)'), 'Replaced table person w/o column "name".');
    #ok($dbh->do('ALTER TABLE person DROP column name'),'Removed the name column from the person table'); ##<won't work
$trans = UR::Context::Transaction->begin();
ok($trans, "DROPPED EMPLOYEE AND UPDATED PERSON began transaction");

    ok($command_obj->execute(), 'Updating schema');
    @changes = get_changes();
    is(scalar(@changes), 15, "found changes for two more dropped tables");


#    $trans->rollback;
#    ok($trans->isa("UR::DeletedRef"), "rolled-back transaction");
#    is(cached_dd_object_count(), $expected_dd_object_count, "no data dictionary objects cached after rollback");
#
#$DB::single = 1;
$trans = UR::Context::Transaction->begin();
ok($trans, "Restarted transaction since some data is not really sync'd at sync_filesystem");
ok($command_obj->execute(), 'Updating schema anew.');


    ok(! UR::Object::Type->get('URT::Employee'), 'Correctly could not load Employee class');
    ok(! UR::Object::Type->get('URT::Car'),'Correctly could not load Car class');

    $personclass = UR::Object::Type->get('URT::Person');
    $personclass->ungenerate;
    $DB::single = 1;
    $personclass->generate;
    ok($personclass, 'Person class loaded');
    is_deeply([sort $personclass->column_names],
            ['PERSON_ID','POSTAL_ADDRESS'],
            'Person object has all the right columns');
    is_deeply([sort $personclass->class_name->property_names],
            ['person_id','postal_address'],
            'Person object has all the right properties');
    is_deeply([$personclass->id_column_names],
            ['PERSON_ID'],
            'Person object has all the right id column names');

    $trans->rollback;
    ok($trans->isa("UR::DeletedRef"), "rolled-back transaction");
    is(cached_dd_object_count(), $expected_dd_object_count, "no data dictionary objects cached after rollback");

# Clean up after now-defunct class module files and SQLIte DB file

cleanup_files();

sub child_db_interaction {
my $dbfile = shift;

    my $pid;
    my $result = IO::Pipe->new();
    my $to_child = IO::Pipe->new();
    if ($pid = fork()) {
        $to_child->writer;
        $to_child->autoflush(1);
        $result->reader();
        my @commands = map {$_ . "\n"} @_;

        foreach my $cmd ( @commands ) {
            $to_child->print($cmd);

            my $result = $result->getline();
            chomp($result);
            my($retval,$string,$dbierr) = split(';',$result);
            return undef unless $retval;
        }

        $to_child->print("exit\n");
        waitpid($pid,0);
        return 1;

    } else {
        $to_child->reader();
        $result->writer();
        $result->autoflush(1);

        my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","");
        unless ($dbh) {
            $result->print("0;can't connect;$DBI::errstr\n");
            exit(1);
        }

        while(my $sql = $to_child->getline()) {
            chomp($sql);
            last if ($sql eq 'exit' || !$sql);

            my $sth = $dbh->prepare($sql);
            unless ($sth) {
                $result->print("0;prepare failed;$DBI::errstr\n");
                $result->print("0;prepare failed;$DBI::errstr\n");
                next;
            }
            my $retval = $sth->execute();
            if ($retval) {
                $result->print($retval . "\n");
            } else {
                $result->print("0;execute failed;$DBI::errstr\n");
            }
        }
        $dbh->commit();

        exit(0);
    } # end child
}



1;
