package Command::CrudUtil;

use strict;
use warnings;

use Params::Validate qw/ :types validate_pos /;

class Command::CrudUtil {
    doc => 'Utils for CRUD commands',
};

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

1;
