use warnings;
use strict;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use UR;
use Test::More tests => 40;

UR::Object::Type->define(
    class_name => 'Acme::ParentCommand',
    is => 'Command',
    has => [
        param_a => { is => 'String', is_optional => 1 },
        param_b => { is => 'String', is_optional => 0 },
    ],
);

UR::Object::Type->define(
    class_name => 'Acme::ChildCommand',
    is => 'Acme::ParentCommand',
    has => [
        param_a => { is => 'String', is_optional => 0 },
    ],
);

sub Acme::ParentCommand::execute { 1; }

sub Acme::ChildCommand::execute { 1; }

my $usage_string = '';
my $callback = sub {
        my $self = shift;
        $usage_string = shift;
        $usage_string =~ s/\x{1b}\[\dm//g;  # Remove ANSI escape sequences
    };

Acme::ParentCommand->dump_usage_messages(0);
Acme::ParentCommand->usage_messages_callback($callback);
Acme::ChildCommand->dump_usage_messages(0);
Acme::ChildCommand->usage_messages_callback($callback);

$usage_string = '';
my $rv = Acme::ParentCommand->_execute_with_shell_params_and_return_exit_code('--help');
ok(! $rv, 'Parent command executed');
like($usage_string, qr(REQUIRED ARGUMENTS\s+param-b\s+String), 'Parent help text lists param-b as required');
like($usage_string, qr(OPTIONAL ARGUMENTS\s+param-a\s+String), 'Parent help text lists param-a as optional');
unlike($usage_string, qr(REQUIRED ARGUMENTS\s+param-a\s+String), 'Parent help text does not list param-a as required');
unlike($usage_string, qr(OPTIONAL ARGUMENTS\s+param-b\s+String), 'Parent help text does not list param-b as optional');

$usage_string = '';
$rv = Acme::ChildCommand->_execute_with_shell_params_and_return_exit_code('--help');
ok(! $rv, 'Child command executed');
like($usage_string, qr(param-a\s+String), 'Child help text mentions param-a');
like($usage_string, qr(param-b\s+String), 'Child help text mentions param-b');
unlike($usage_string, qr(OPTIONAL ARGUMENTS\s+param-a\s+String), 'Child help text does not list param-a as optional');






