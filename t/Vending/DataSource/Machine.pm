package Vending::DataSource::Machine;

use strict;
use warnings;

use Vending;

class Vending::DataSource::Machine {
    is => [ 'UR::DataSource::SQLite', 'UR::Singleton' ],
};

use File::Temp;
sub server {
    our $FILE;
    unless ($FILE) {
        (undef, $FILE) = File::Temp::tempfile('ur_testsuite_vend_XXXX',
                                              OPEN => 0,
                                              UNKINK => 0,
                                              TMPDIR => 1,
                                              SUFFIX => '.sqlite3');
        print STDERR "Using DB file $FILE\n";
    }
    return $FILE;
}

# Don't print warnings about loading up the DB if running in the test harness
# Similar code exists in URT::DataSource::Meta.
sub _dont_emit_initializing_messages {
    my($msgobj, $dsobj, $msgtype) = @_;

    my $message = $msgobj->text;
    if ($message !~ m/^Re-creating/) {
        $dsobj->message_callback($msgtype, undef);
        my $msg_method = $msgtype . '_message';
        $dsobj->$msg_method($message);
        $dsobj->message_callback($msgtype, \&_dont_emit_initializing_messages);
    }
}

if ($ENV{'HARNESS_ACTIVE'}) {
    # don't emit messages while running in the test harness
    __PACKAGE__->message_callback('warning', \&_dont_emit_initializing_messages);
}


END {
    our $FILE;
    unlink $FILE;
}


1;
