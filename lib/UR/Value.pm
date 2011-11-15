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

    # Auto generate the object on the fly.
    my $id_list = $rule->value_for_id;
    unless (defined $id_list) {
        #$DB::single = 1;
        Carp::croak "No id specified for loading members of an infinite set ($class)!"
    }

    my $class_meta = $class->__meta__;

    my(@headers,@values);
    if (ref($id_list) ne 'ARRAY') {
        $id_list = [ $id_list ];
    }

    foreach my $id ( @$id_list ) {
        my @p = (id => $id);
        my %p;
        if (my $alt_ids = $class_meta->{id_by}) {
            if (@$alt_ids == 1) {
                push @p, $alt_ids->[0] => $id;
            }
            else {
                my ($rule, %extra) = UR::BoolExpr->resolve_normalized($class, $rule);
                push @p, $rule->params_list;
            }
        }
        %p = @p;
        unless (@headers) {
            @headers = keys %p;
        }
        push @values, [ values %p ]
    }

    return \@headers, \@values;
}

1;

