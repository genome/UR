
use strict;
use warnings;

use Test::More tests => 4;
use Test::Deep qw(cmp_bag);

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

use UR;

UR::Object::Type->define(
    class_name => 'URT::Person',
    has => [
        name => {
            is => 'Text',
        },
        nicknames => {
            is => 'Text',
            is_many => 1,
        },
    ],
);

my $nickname = 'Alyosha';
my $person = URT::Person->create(name => 'Alexei', nicknames => $nickname);
is($person->nicknames, $nickname, 'set (and retrieved) a single nickname');

$nickname = 'Alex';
$person->nicknames($nickname);
is($person->nicknames, $nickname, 'updated (and retrieved) a single nickname');

my @nicknames = qw(Rose Anna Roseanne Annie);
my $person2 = URT::Person->create(name => 'Roseanna', nicknames => \@nicknames);
cmp_bag([$person2->nicknames], \@nicknames, 'set (and retrieved) several nicknames');

@nicknames = qw(Rosy Anne);
$person2->nicknames(\@nicknames);
cmp_bag([$person2->nicknames], \@nicknames, 'updated (and retrieved) several nicknames correctly');
