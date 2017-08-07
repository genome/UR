package Command::CrudUtil;

use strict;
use warnings;

use Params::Validate qw/ :types validate_pos /;

class Command::CrudUtil {
    doc => 'Utils for CRUD commands',
};

sub camel_case_to_string {
    my ($class, $string) = validate_pos(@_, {isa => __PACKAGE__}, {is => SCALAR});
    join(' ', map { lc } split( /(?=(?<![A-Z])[A-Z])|(?=(?<!\d)\d)/, $string)); #split on the first capital or the start of a number
}

sub display_name_for_value {
    my ($class, $value) = @_;

    return 'NULL' if not defined $value;

    my $ref = ref $value;
    if ( $ref eq 'ARRAY' and @$value > 10 ) {
        return scalar @$value.' items';
    }

    my @display_names;
    for my $val ( $ref eq 'ARRAY' ? @$value : $value ) {
        if ( not defined $val ) {
            push @display_names, 'NULL';
        }
        elsif ( not Scalar::Util::blessed($val) ) {
            push @display_names, $val;
        }
        elsif ( my $display_name_sub = $val->can('__display_name__') ) {
            push @display_names, $display_name_sub->($val);
        }
        else {
            push @display_names, $val->id;
        }
    }

    join(" ", @display_names);
}

sub display_id_for_value {
    my ($class, $value) = @_;

    if ( not defined $value ) {
        'NULL';
    }
    elsif ( ref($value) eq 'HASH' or ref($value) eq 'ARRAY' ) {
        die 'Do not pass HASH or ARRAY to display_id_for_value!';
    }
    elsif ( not Scalar::Util::blessed($value) ) {
        $value;
    }
    elsif ( $value->can('id') ) {
        $value->id;
    }
    else { # stringify
        "$value";
    }
}

sub resolve_incoming_property_names {
    my ($class, $names) = @_;

    return if not $names;

    my @names;
    my $ref = ref $names;
    if ( not $ref ) {
        @names = $names;
    }
    elsif ( $ref eq 'ARRAY' ) {
        @names = @$names;
    }
    else {
        die "Dunno how to incoming_names_to_array with ".Data::Dumper::Dumper($names);
    }

    map { s/_id$//; $_; } @names; # remove trailing '_id'
}

1;
