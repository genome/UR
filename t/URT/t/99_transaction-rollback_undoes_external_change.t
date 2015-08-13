use strict;
use warnings;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../..";

use URT;
use Test::More tests => 4;

UR::Object::Type->define(
    class_name => 'URT::Thing',
    id_by => 'thing_id',
);

my $thing = URT::Thing->create(thing_id => '1');

my $undo_call_count = 0;
my $undo = sub {
    $undo_call_count++;
};

my $c = UR::Context::Transaction->log_change(
    $thing, $thing->class, $thing->id, 'external_change', $undo
);
isa_ok($c, 'UR::Change', 'created a change');
is($c->undo_data, $undo, 'undo subrountine properly configured');

UR::Context->rollback();
is($undo_call_count, 1, 'undo fired');

UR::Context->rollback();
is($undo_call_count, 1, 'undo did not fire again');
