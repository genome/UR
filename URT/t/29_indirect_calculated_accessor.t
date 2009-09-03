use warnings;
use strict;

use URT;
use Test::More tests => 11;


ok(setup(), 'Create initial schema, data and classes');

my $boss = URT::Boss->get(1);
ok($boss, 'Got boss id 1');

is($boss->full_name, 'Bob Smith', "Boss' full name is correct");
is($boss->upper_first_name, 'BOB', "Boss' first name in all caps (presumedly from SQL)");

my $empl = URT::Employee->get(name => 'Joe');
ok($empl, 'Got an employee');
is($empl->boss_name, 'Bob Smith', "Employee's boss' name is correct");
is($empl->boss_upper_first_name, 'BOB', "Employee's boss' first name in all caps");

$empl = URT::Employee->get(name => 'Foo');
ok($empl, 'Got another employee with a different boss not yet loaded');
is($empl->boss_name, 'Fred Jones', "Employee's boss' name is correct");
is($empl->boss_upper_first_name, 'FRED', "Employee's boss' first name in all caps");


ok(cleanup(), 'Removed schema');

# define the data source, create a table and classes for it
sub setup {

    my $dbh = URT::DataSource::SomeSQLite->get_default_dbh || return;
    $dbh->do('create table if not exists BOSS (boss_id int, first_name varchar, last_name varchar, company varchar)') || return;
    $dbh->do('create table if not exists EMPLOYEE (emp_id int, name varchar, boss_id int CONSTRAINT boss_fk references BOSS(BOSS_ID))') || return;

    my $boss_sth = $dbh->prepare('insert into BOSS (boss_id, first_name, last_name, company) values (?,?,?,?)') || return;
    $boss_sth->execute(1, 'Bob', 'Smith', 'CoolCo') || return;
    $boss_sth->execute(2, 'Fred', 'Jones', 'Data Inc') || return;
    $boss_sth->finish();

    my $employee_sth = $dbh->prepare('insert into EMPLOYEE (emp_id, name, boss_id) values (?,?,?)') || return;
    $employee_sth->execute(1,'Joe', 1) || return;
    $employee_sth->execute(2,'Mike', 1) || return;
    $employee_sth->execute(3,'Foo', 2) || return;
    $employee_sth->execute(4,'Bar', 2) || return;
    $employee_sth->execute(5,'Baz', 2) || return;
    
    $dbh->commit() || return;

    UR::Object::Type->define(
        class_name => "URT::Boss",
        id_by => 'boss_id',
        has => [
            boss_id       => { type => "Number" },
            first_name    => { type => "String" },
            last_name     => { type => "String" },
            full_name     => { calculate_from => ['first_name','last_name'],
                               calculate => '$first_name . " " . $last_name',
                             },
            upper_first_name => { calculate_from => 'first_name',
                                  calculate_sql  => 'upper(first_name)' },
            company       => { type => "String" },

        ],
        table_name => 'BOSS',
        data_source => 'URT::DataSource::SomeSQLite',
    );
    UR::Object::Type->define(
        class_name => 'URT::Employee',
        id_by => 'emp_id',
        has => [
            emp_id => { type => "Number" },
            name => { type => "String" },
            boss_id => { type => 'Number'},
            boss => { type => "URT::Boss", id_by => 'boss_id' },
            boss_name => { via => 'boss', to => 'full_name' },
            boss_upper_first_name => { via => 'boss', to => 'upper_first_name' },
            company   => { via => 'boss' },
        ],
        table_name => 'EMPLOYEE',
        data_source => 'URT::DataSource::SomeSQLite',
    );

    return 1;
}


sub cleanup {
    my $dbh = URT::DataSource::SomeSQLite->get_default_dbh || return;
    $dbh->do('drop table BOSS') || return;
    $dbh->do('drop table EMPLOYEE') || return;
   
    return 1;
}
