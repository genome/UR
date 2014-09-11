use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";

use Test::More tests => 2;
use Test::Fatal qw(exception);
use Test::Deep qw(cmp_bag);

use UR;
use URT::DataSource::SomeSQLite;

my $dbh = URT::DataSource::SomeSQLite->get_default_handle;
$dbh->do(q(create table team (id integer PRIMARY KEY, name text)));
$dbh->do(q(create table member (id integer PRIMARY KEY, name text, team_id text, role text)));

$dbh->do(q(insert into team values (1, 'Three Stooges')));
$dbh->do(q(insert into member values (1, 'Larry', 1, 'member')));
$dbh->do(q(insert into member values (2, 'Curly', 1, 'member')));
$dbh->do(q(insert into member values (3, 'Moe',   1, 'admin')));

$dbh->do(q(insert into team values (2, "Who's the Boss?")));
$dbh->do(q(insert into member values (4, 'Tony Micelli',     2, 'admin')));
$dbh->do(q(insert into member values (5, 'Angela Bower',     2, 'admin')));
$dbh->do(q(insert into member values (6, 'Samantha Micelli', 2, 'member')));
$dbh->do(q(insert into member values (7, 'Jonathan Bower',   2, 'member')));
$dbh->do(q(insert into member values (8, 'Mona Robinson',    2, 'member')));

$dbh->commit();

UR::Object::Type->define(
    class_name => 'Team',
    id_by => 'id',
    has => [
        name => { is => 'Text' },
        members => { is => 'Member', reverse_as => 'team', is_many => 1 },
        admin   => { is => 'Member', reverse_as => 'team', is_many => 0, where => ['role' => 'admin'] },
    ],
    table_name => 'team',
    data_source => 'URT::DataSource::SomeSQLite',
);

UR::Object::Type->define(
    class_name => 'Member',
    id_by => 'id',
    has => [
        name => { is => 'Text' },
        team => { is => 'Team', id_by => 'team_id' },
        role => { is => 'Text', valid_values => [qw(admin member)] },
    ],
    table_name => 'member',
    data_source => 'URT::DataSource::SomeSQLite',
);

subtest 'Three Stooges' => sub {
    plan tests => 4;

    my $team = Team->get(name => 'Three Stooges');
    my $larry = Member->get(name => 'Larry');
    my $curly = Member->get(name => 'Curly');
    my $moe = Member->get(name => 'Moe');

    cmp_bag([$team->members], [$larry, $curly, $moe], 'got members');
    is($team->admin, $moe, 'got admin');

    is(Member->get(team => $team, role => 'admin'), $moe, 'got admin member via a team');
    is(Team->get(admin => $moe), $team, 'got team via admin');
};

subtest q(Who's the Boss?) => sub {
    plan tests => 2;

    my $team = Team->get(name => q(Who's the Boss?));
    is(scalar(() = $team->members), 5, 'got five members');
    ok(exception { $team->admin }, 'got an exception when trying to get the admin');
};
