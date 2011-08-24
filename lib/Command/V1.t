use strict;
use warnings;
use Test::More;
use above 'UR';

UR::Object::Type->define(
    class_name => 'Test::Command',
    is => ['Command::V1'],
);

my $command = Test::Command->create;
ok($command, 'Command Object created');
is($command->status_message('foo'),'foo','Returns message in scalar context');
my @ret = $command->status_message('foo');
is($ret[0],'foo','Returns message as first element in list context');
is($ret[1],'main','Returns package as second element in list context');
is($ret[2],'Command/V1.t','Returns file name as third element in list context');
ok($ret[3] =~ /\d+/,'Returns line number as fourth element in list context');
done_testing;
