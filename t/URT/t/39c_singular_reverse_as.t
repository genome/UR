use strict;
use warnings;

use Test::More tests => 3;
use Test::Fatal qw(exception);
use Test::Deep qw(cmp_bag);

use UR;

UR::Object::Type->define(
    class_name => 'Team',
    id_generator => '-uuid',
    has => [
        name => { is => 'Text' },
        members => { is => 'Member', reverse_as => 'team', is_many => 1 },
        admin   => { is => 'Member', reverse_as => 'team', is_many => 0, where => ['role' => 'admin'] },
    ],
);

UR::Object::Type->define(
    class_name => 'Member',
    id_generator => '-uuid',
    has => [
        name => { is => 'Text' },
        team => { is => 'Team', id_by => 'team_id' },
        role => { is => 'Text', valid_values => [qw(admin member)] },
    ],
);

my $team = Team->create(name => 'A');
my $larry = Member->create(
    name => 'Larry',
    team => $team,
    role => 'member',
);
my $curly = Member->create(
    name => 'Curly',
    team => $team,
    role => 'member',
);
my $moe = Member->create(
    name => 'Moe',
    team => $team,
    role => 'admin',
);

cmp_bag([$team->members], [$larry, $curly, $moe], 'got members');
is($team->admin, $moe, 'got admin');

my $harry = Member->create(
    name => 'Harry',
    team => $team,
    role => 'admin',
);
ok(exception { $team->admin }, 'got exception when there are two admins');
