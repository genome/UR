use strict;
use warnings;

use Test::More tests => 3;

use UR;

UR::Object::Type->define(
    class_name => 'Sports::Player',
    has => [
        name => { is => 'Text' },
    ],
    has_optional => [
        team_id => { is => 'Text' },
        team => {
            is => 'Sports::Team',
            id_by => 'team_id',
        },
    ],
);

UR::Object::Type->define(
    class_name => 'Sports::Team',
    has => [
        name => {
            is => 'Text',
        },
    ],
    has_optional => [
        players => {
            is => 'Sports::Player',
            is_many => 1,
            reverse_as => 'team',
        },
    ],
);

my $lakers = Sports::Team->create(name => 'Lakers');
my $mj = Sports::Player->create(team_id => $lakers->id, name => 'Magic Johnson');
is_deeply([$lakers->players], [$mj], 'lakers have mj');

my $copied_team = $lakers->copy();
is_deeply([$copied_team->players], [], 'copied team has no players');
is($copied_team->name, $lakers->name, 'name was copied');
