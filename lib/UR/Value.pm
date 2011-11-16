package UR::Value;

use strict;
use warnings;

require UR;
our $VERSION = "0.35"; # UR $VERSION;

our @CARP_NOT = qw( UR::Context );

UR::Object::Type->define(
    class_name => 'UR::Value',
    is => 'UR::Object',
    has => ['id'],
    data_source => 'UR::DataSource::Default',
);

sub __display_name__ {
    return shift->id;
}

sub __load__ {
    my $class = shift;
    my $rule = shift;
    my $expected_headers = shift;

    my $id = $rule->value_for_id;
    unless (defined $id) {
        #$DB::single = 1;
        Carp::croak "No id specified for loading members of an infinite set ($class)!"
    }

    my $class_meta = $class->__meta__;

    my @values;
    foreach my $header ( @$expected_headers ) {
        my $value = $rule->value_for($header);
        push @values, $value;
    }

    return $expected_headers, [\@values];
}

1;
