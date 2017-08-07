package Command::Copy;

use strict;
use warnings FATAL => 'all';

class Command::Copy {
    is => 'Command::V2',
    is_abstract => 1,
    has => {
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

    my $tx = UR::Context::Transaction->begin;

    my $copy = $self->source->copy();

    for my $change ($self->changes) {
        my ($key, $op, $value) = $change =~ /^(.+?)(=|\+=|\-=|\.=)(.*)$/;
        $self->fatal_message("Invalid change: $change") unless $key and defined $op;
        $self->fatal_message('Invalid property %s for %s', $key, $copy->__display_name__) if !$copy->can($key);

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

    if (!$tx->commit ) {
        $tx->rollback;
        $self->fatal_message('Failed to commit software transaction!');
    }

    $self->status_message("NEW\t%s\t%s", $copy->class, $copy->__display_name__);
    1;
}

1;
