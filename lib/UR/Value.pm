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

package UR::Value::Type;

sub get_composite_id_decomposer {
    my $class_meta = shift;

    unless ($class_meta->{get_composite_id_decomposer}) {
        my @id_property_names = $class_meta->id_property_names;
        my $instance_class = $class_meta->class_name;
        if (my $decomposer = $instance_class->can('__deserialize_id__')) {
            $class_meta->{get_composite_id_decomposer} = sub {
                my @ids = (ref($_[0]) and ref($_[0]) eq 'ARRAY')
                            ? @{$_[0]}
                            : ( $_[0] );
                my @retval;
                if (@ids == 1) {
                    my $h = $instance_class->$decomposer($ids[0]);
                    @retval = @$h{@id_property_names};

                } else {
                    @retval = map { [] } @id_property_names;  # initialize n empty lists
                    foreach my $id ( @ids ) {
                        my $h = $instance_class->$decomposer($id);
                        #my @h = @$h{@id_property_names};
                        for (my $i = 0; $i < @id_property_names; $i++) {
                            push @{ $retval[$i] }, $h->{$id_property_names[$i]};
                        }
                    }
                }
                return @retval;
            };

        } else {
            $decomposer = $class_meta->SUPER::get_composite_id_decomposer();
            $class_meta->{get_composite_id_decomposer} = $decomposer;
        }
    }
    return $class_meta->{get_composite_id_decomposer};
}

sub get_composite_id_resolver {
    my $class_meta = shift;
    unless ($class_meta->{get_composite_id_resolver}) {
        my @id_property_names = $class_meta->id_property_names;
        my $instance_class = $class_meta->class_name;
        if (my $resolver = $instance_class->can('__serialize_id__')) {
            $class_meta->{get_composite_id_resolver} = sub {
                my %h = map { $_ => shift } @id_property_names;
                return $instance_class->__serialize_id__(\%h);
            };

        } else {
            $resolver = $class_meta->SUPER::get_composite_id_resolver();
            $class_meta->{get_composite_id_resolver} = $resolver;
        }
    }
    return $class_meta->{get_composite_id_resolver};
}



1;
