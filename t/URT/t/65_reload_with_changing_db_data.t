use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;

use Test::More tests => 270;
use URT::DataSource::SomeSQLite;

END {
    unlink URT::DataSource::SomeSQLite->server;
}

my $dbh = &setup_classes_and_db();


# The DB table the test updates changes depending on which class we're futzing with
my %table_for_class = ('URT::Thing' => 'thing',
                       'URT::ParentThing' => 'childthing',
                       'URT::ChildThing' => 'childthing',
                       'URT::ReblessParentThing' => 'reblessparentthing',
                       'URT::ReblessChildThing' => 'reblessparentthing',
                      );

# Context exception messages complain about the class the object lives in, not the one it's loaded from
my %complaint_class = ('URT::Thing' => 'URT::Thing',
                       'URT::ParentThing' => 'URT::ChildThing',
                       'URT::ChildThing' => 'URT::ChildThing',
                       'URT::ReblessParentThing' => 'URT::ReblessParentThing',
                       'URT::ReblessChildThing' => 'URT::ReblessParentThing',
                     );

my $obj_id = 1; 
foreach my $test_class ( 'URT::Thing', 'URT::ParentThing', 'URT::ChildThing', 'URT::ReblessParentThing', 'URT::ReblessChildThing') {
    diag("Working on class $test_class");
    UR::DBI->no_commit(0);

    my $test_table = $table_for_class{$test_class};

    my $this_pass_obj_id = $obj_id++;

    my $thing = $test_class->get($this_pass_obj_id);
    ok($thing, "Got a $test_class object");
    is($thing->value, 1, 'its value is 1');

    my $cx = UR::Context->current();
    ok($cx, 'Got the current context');
    
    # First test.  Make no changes and reload the object 
    ok(eval { $cx->reload($thing) }, 'Reloaded object after no changes');
    is($@, '', 'No exceptions during reload');
    ok(!scalar($thing->__changes__), 'No changes, as expected');
    
    
    # Next test, Make a change to the database, no change to the object and reload
    # It should update the object's value to match the newly reloaded DB data
    ok($dbh->do("update $test_table  set value = 2 where thing_id = $this_pass_obj_id"), 'Updated value for thing in the DB to 2');
    ok(eval { $cx->reload($thing) }, 'Reloaded object again');
    is($@, '', 'No exceptions during reload');
    is($thing->value, 2, 'its value is now 2');
    ok(!scalar($thing->__changes__), 'No changes. as expected');

    
    # make a change to the object, no change to the DB
    ok($thing->value(3), 'Changed the object value to 3');
    is(scalar($thing->__changes__), 1, 'One change, as expected');
    ok(eval { $cx->reload($thing) },' Reload object');
    is($@, '', 'No exceptions during reload');
    is($thing->value, 3, 'Value is still 3');
    is(scalar($thing->__changes__), 1, 'Still one change, as expected');
    
    # Make a change to the DB, and the exact same change to the object
    ok($dbh->do("update $test_table set value = 3 where thing_id = $this_pass_obj_id"), 'Updated value for thing in the DB to 3');
    ok($thing->value(3), "Changed the object's value to 3");
    ok($thing->__changes__, 'Before reloading, object says it has changes');
    ok(eval { $cx->reload($thing) },'Reloaded object again');
    is($@, '', 'No exceptions during reload');
    is($thing->value, 3, 'Value is 3');
    ok(! scalar($thing->__changes__), 'After reloading, object says it has no changes');
    
    
    
    # Make a change to the DB data, and a different cahange to the object.  This should fail
    ok($dbh->do("update $test_table set value = 4 where thing_id = $this_pass_obj_id"), 'Updated value for thing in the DB to 4');
    ok($thing->value(5), "Changed the object's value to 5");
    ok(! eval { $cx->reload($thing) },'Reloading fails, as expected');
    my $message = $@;
    $message =~ s/\s+/ /gm;   # collapse whitespace
    my $complaint_class = $complaint_class{$test_class};
    like($message,
         qr/A change has occurred in the database for $complaint_class property 'value' on object ID $this_pass_obj_id from '3' to '4'. At the same time, this application has made a change to that value to '5'./,
         'Exception message looks correct');
    is($thing->value, 5, 'Value is 5');
    
    
    ok(UR::DBI->no_commit(1), 'Turned on no_commit');
    ok($thing->value(6), "Changed the object's value to 6");
    ok(UR::Context->commit(), 'calling commit()');
    ok($dbh->do("update $test_table set value = 6 where thing_id = $this_pass_obj_id"), 'Updated value for thing in the DB to 6');
    ok(eval { $cx->reload($thing) },'Reloading object again');
    is($@, '', 'No exceptions during reload');
    is($thing->value, 6, 'Value is 6');
    
    ok(UR::DBI->no_commit(1), 'Turned on no_commit');
    ok($thing->value(7), "Changed the object's value to 7");
    ok(UR::Context->commit(), 'calling commit()');
    ok($dbh->do("update $test_table set value = 7 where thing_id = $this_pass_obj_id"), 'Updated value for thing in the DB to 7');
    ok($thing->value(8), 'Changed object value to 8');
# FIXME - this seems to do the wrong thing in _most_ cases.
# I'd expect the value to remain 8, db_committed to be 6? and db_saved_uncommitted to be 7
    ok(eval { $cx->reload($thing) },'Reloading object again');
    is($@, '', 'No exceptions during reload');
    #is($thing->value, 7, 'Value is 7');
    is($thing->value, 8, 'Value is 8');
    
    ok(UR::DBI->no_commit(1), 'Turned on no_commit');
    ok($thing->value(9), "Changed the object's value to 9");
    ok(UR::Context->commit(), 'calling commit()');
    ok($dbh->do("update $test_table set value = 10 where thing_id = $this_pass_obj_id"), 'Updated value for thing in the DB to 10');
    ok($thing->value(11), 'Changed object value to 11');
    ok(! eval { $cx->reload($thing) },'Reloading fails, as expected');
    $message = $@;
    $message =~ s/\s+/ /gm;   # collapse whitespace
    like($message,
         qr/A change has occurred in the database for $complaint_class property 'value' on object ID $this_pass_obj_id from '7' to '10'. At the same time, this application has made a change to that value to '11'/,
         'Exception message looks correct');
    is($thing->value, 11, 'Value is 11');
}





 




sub setup_classes_and_db {
    my $dbh = URT::DataSource::SomeSQLite->get_default_dbh;

    ok($dbh, 'Got DB handle');

    ok( $dbh->do("create table thing (thing_id integer PRIMARY KEY, value integer)"),
        'created thing table');

    ok($dbh->do("create table parentthing (thing_id integer PRIMARY KEY, parentvalue integer) "),
         'created parentthing table');

    ok($dbh->do("create table childthing(thing_id integer PRIMARY KEY references parentthing(thing_id), value integer)"),
         'created subthing table');

    ok($dbh->do("create table reblessparentthing (thing_id integer PRIMARY KEY, value integer) "),
         'created reblessparentthing table');

    my $sth = $dbh->prepare('insert into thing values (?,?)');
    ok($sth, 'Prepared insert statement');
    foreach my $val ( 1,2,3,4,5 ) {   # We need one item for each class under test at the top
        $sth->execute($val,1);
    }
    $sth->finish;

    my $parentsth = $dbh->prepare('insert into parentthing values (?,?)');
    ok($parentsth, 'Prepared parentthing insert statement');
    my $childsth = $dbh->prepare('insert into childthing values (?,?)');
    ok($childsth, 'Prepared childthing insert statement');
    my $parent2sth = $dbh->prepare('insert into reblessparentthing values (?,?)');
    ok($parent2sth, 'Prepared reblessparentthing insert statement');
    foreach my $val ( 1,2,3,4,5 ) {   # one item for each class here, too
        $parentsth->execute($val,1);
        $childsth->execute($val,1);
        $parent2sth->execute($val,1);
    }
    $parentsth->finish;
    $childsth->finish;
    $parent2sth->finish;

    ok($dbh->commit(), 'DB commit');

    # A class we can load directly
    UR::Object::Type->define(
        class_name => 'URT::Thing',
        id_by => 'thing_id',
        has => [ 'value' ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'thing',
    );

    # A pair of classes, one that inherits from another.  The child class
    # has a table that gets joined
    sub URT::ParentThing::resolve_subclass_name {
        return 'URT::ChildThing';    # All are ChildThings
    }
    UR::Object::Type->define(
        class_name => 'URT::ParentThing',
        sub_classification_method_name => 'resolve_subclass_name',
        id_by => 'thing_id',
        has => [ 'parentvalue' ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'parentthing',
        is_abstract => 1,
    );

    UR::Object::Type->define(
        class_name => 'URT::ChildThing',
        is => 'URT::ParentThing',
        id_by => 'thing_id',
        has => [ 'value' ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'childthing',
    );


    # Another pair of classes.  This time, the child class does not have its own table.
    sub URT::ReblessParentThing::resolve_subclass_name {
        return 'URT::ReblessChildThing';    # All are ChildThings
    }
    UR::Object::Type->define(
        class_name => 'URT::ReblessParentThing',
        sub_classification_method_name => 'resolve_subclass_name',
        id_by => 'thing_id',
        has => [ 'value' ],
        data_source => 'URT::DataSource::SomeSQLite',
        table_name => 'reblessparentthing',
        is_abstract => 1,
    );

    UR::Object::Type->define(
        class_name => 'URT::ReblessChildThing',
        is => 'URT::ReblessParentThing',
    );

    return $dbh;
}
        
   


