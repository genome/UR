package Command::Copy;

use strict;
use warnings FATAL => 'all';

use Try::Tiny qw(try catch);

class Command::Copy {
    is => 'Command::V2',
    is_abstract => 1,
    has => {
        source => {
            is => 'UR::Object',
            shell_args_position => 1,
        },
        changes => {
            is => 'Text',
            is_many => 1,
            doc => 'A name/value comma-separated list of changes',
        },
    },
};

sub help_detail {
<<HELP;
    Any non-delegated, non-ID properties may be specified with an operator and a value.

    Valid operators are '=', '+=', '-=', and '.='; function is same as in Perl.
    Example:
    --changes "name.=-RT101912,foo=bar"\n\n),

    A value of 'undef' may be used to pass a Perl undef as the value.  Either `foo=` or `foo=''` can be used to set the value to an empty string.
HELP
}

sub execute {
    my $self = shift;

    my $tx = UR::Context::Transaction->begin();

    my $error;
    my $copy = try {
        my $copy = $self->source->copy();

        for my $change ($self->changes) {
            my ($key, $op, $value) = $change =~ /^(.+?)(=|\+=|\-=|\.=)(.*)$/;
            die ("Invalid change: $change") unless $key && $op;
            die sprintf('Invalid property %s for %s', $key, $copy->__display_name__) if !$copy->can($key);

            $value = undef if $value =~ /^undef$/i;

            if ($op eq '=') {
                $copy->$key($value);
            }
            elsif ($op eq '+=') {
                $copy->$key($copy->$key + $value);
            }
            elsif ($op eq '-=') {
                $copy->$key($copy->$key - $value);
            }
            elsif ($op eq '.=') {
                $copy->$key($copy->$key . $value);
            }
        }

        die 'Failed to commit!' if !$tx->commit;
        $copy;
    }
    catch {
        $tx->rollback;
        $error = $_ || 'Unknown error';
        return;
    };

    $self->fatal_message('Failed to create new %s: %s', $self->source->class, $error) if !$copy;

    $self->status_message('Created new %s with ID %s', $copy->class, $copy->id);
    1;
}

1;
