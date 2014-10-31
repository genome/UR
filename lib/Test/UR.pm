package Test::UR;
use base 'Test::Builder::Module';

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(txtest);

sub txtest {
    my ($name, $subtests, @args) = @_;
    my $tb = __PACKAGE__->builder;
    my $tx = UR::Context::Transaction->begin();
    my $rv = $tb->subtest($name, $subtests, @args);
    $tx->rollback;
    return $rv;
};

1;
