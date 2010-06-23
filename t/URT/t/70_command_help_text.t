use warnings;
use strict;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use UR;
use Test::More tests => 13;

UR::Object::Type->define(
    class_name => 'Acme::ParentCommand',
    is => 'Command',
    has => [
        param_a => { is => 'String', is_optional => 1, doc => 'Some documentation for param a' },
        param_b => { is => 'String', is_optional => 0 },
        param_c => { is => 'String', doc => 'Parent documentation for param c' },
    ],
);

UR::Object::Type->define(
    class_name => 'Acme::ChildCommand',
    is => 'Acme::ParentCommand',
    has => [
        param_a => { is => 'String', is_optional => 0 },
        param_c => { is => 'String', doc => 'Child documentation for param c' },
    ],
);

sub Acme::ParentCommand::execute { 1; }

sub Acme::ChildCommand::execute { 1; }

my $usage_string = '';
my $callback = sub {
        my $self = shift;
        $usage_string = shift;
        $usage_string =~ s/\x{1b}\[\dm//g;  # Remove ANSI escape sequences for color/underline
    };

Acme::ParentCommand->dump_usage_messages(0);
Acme::ParentCommand->usage_messages_callback($callback);
Acme::ChildCommand->dump_usage_messages(0);
Acme::ChildCommand->usage_messages_callback($callback);

$usage_string = '';
my $rv = Acme::ParentCommand->_execute_with_shell_params_and_return_exit_code('--help');
is($rv,1, 'Parent command executed');
like($usage_string, qr(USAGE\s+acme parent-command --param-b=\?\s+--param-c=\?\s+\[--param-a=\?\]), 'Parent help text usage is correct');
like($usage_string, qr(REQUIRED ARGUMENTS\s+param-b\s+String), 'Parent help text lists param-b as required');
like($usage_string, qr(OPTIONAL ARGUMENTS\s+param-a\s+String\s+Some documentation for param a), 'Parent help text lists param-a as optional');
like($usage_string, qr(param-c\s+String\s+Parent documentation for param c), 'Parent help text for param c');
unlike($usage_string, qr(REQUIRED ARGUMENTS\s+param-a\s+String), 'Parent help text does not list param-a as required');
unlike($usage_string, qr(OPTIONAL ARGUMENTS\s+param-b\s+String), 'Parent help text does not list param-b as optional');

$usage_string = '';
$rv = Acme::ChildCommand->_execute_with_shell_params_and_return_exit_code('--help');
is($rv,1, 'Child command executed');
like($usage_string, qr(USAGE\s+acme child-command --param-a=\?\s+--param-b=\?\s+--param-c=\?), 'Child help text usage is correct');
like($usage_string, qr(param-a\s+String\s+Some documentation for param a), 'Child help text mentions param-a with parent documentation');
like($usage_string, qr(param-b\s+String), 'Child help text mentions param-b');
like($usage_string, qr(param-c\s+String\s+Child documentation for param c), 'Child help text mentions param-c with child documentation');
unlike($usage_string, qr(OPTIONAL ARGUMENTS\s+param-a\s+String), 'Child help text does not list param-a as optional');






