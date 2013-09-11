package UR::Value;

use strict;
use warnings;

require UR;
our $VERSION = "0.41"; # UR $VERSION;

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
$DB::single = 1;
    my $id = $rule->value_for_id;
    unless (defined $id) {
        #$DB::single = 1;
        Carp::croak "Can't load an infinite set of $class.  Some id properties were not specified in the rule $rule";
    }

    if (ref($id) and ref($id) eq 'ARRAY') {
        # We're being asked to load up more than one object.  In the basic case, this is only
        # possible if the rule _only_ contains ID properties.  For anything more complicated,
        # the subclass should implement its own behavior

        my $class_meta = $class->__meta__;

        my %id_properties = map { $_ => $rule->value_for($_) } $class_meta->all_id_property_names;
        my @non_id = grep { ! $id_properties{$_} } $rule->template->_property_names;
        if (@non_id) {
            Carp::croak("Cannot load class $class via UR::DataSource::Default when 'id' is a listref and non-id properties appear in the rule:" . join(', ', @non_id));
        }
        my $count = @$expected_headers;

        my @rows;
        for (my $row_n = 0; $row_n < @$id; $row_n++) {
            my @row = map { $id_properties{$_}[$row_n] } @$expected_headers;
            push @rows,\@row;
        }

        #my $listifier = sub { my $c = $count; my @l; push(@l,$_[0]) while ($c--); return \@l };
        return ($expected_headers, \@rows);
    }


    my @values;
    foreach my $header ( @$expected_headers ) {
        my $value = $rule->value_for($header);
        push @values, $value;
    }

    return $expected_headers, [\@values];
}

sub underlying_data_types {
    return ();
}

1;
