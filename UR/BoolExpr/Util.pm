
package UR::BoolExpr::Util;

# Non-OO Utility methods for the rule modules.

use strict;
use warnings;

use Scalar::Util qw(blessed);
use Data::Dumper;
use FreezeThaw;

# Because the id is actually a full data structure we need some separators.
# Note that these are used for the common case, where FreezeThaw is for arbitrarily complicated rule identifiers.

our $id_sep = chr(29);          # spearetes id property values instead of the old \t
our $record_sep = chr(30);      # within an property value, delimits a distinct values
our $unit_sep = chr(31);        # seperates items within a single value

our $null_value = chr(21);      # used for undef/null
our $empty_string = chr(28);    # used for ""
our $empty_list = chr(20);      # used for []

sub values_to_value_id_frozen {
    my $self = shift;
    
    my $frozen = FreezeThaw::safeFreeze(@_);
    return "F:" . $frozen;
}

sub value_id_to_values_frozen {
    my $self = shift;
    my $value_id = shift;

    return FreezeThaw::thaw($value_id);
}

sub values_to_value_id {
    my $self = shift;
    my $value_id = "";

    for my $value (@_) {

        if (not defined $value ) {
            $value_id .= $null_value . $record_sep;
        }
        elsif ($value eq "") {
            $value_id .= $empty_string . $record_sep;
        }
        elsif (ref($value) eq "ARRAY") {            
            if (@$value == 0) {
                $value_id .= $empty_list;
            }
            else {
                for my $value2 (@$value) {
                    if (not defined $value2 ) {
                        $value_id .= $null_value . $unit_sep;
                    }
                    elsif ($value2 eq "") {
                        $value_id .= $empty_string . $unit_sep;
                    }
                    else {
                        if ($value2 =~ m/($unit_sep|$record_sep)/) {
                            return $self->values_to_value_id_frozen(@_);
                        }
                        $value_id .= $value2 . $unit_sep;
                    }                
                }
            }
            $value_id .= $record_sep;
        }
        else {
            if (ref($value) or $value =~ m/($unit_sep|$record_sep)/) {
                return $self->values_to_value_id_frozen(@_);
            }
            $value_id .= $value . $record_sep;
        }        
    }
    return "O:" . $value_id;
}

sub value_id_to_values {
    my $self = shift;
    my $value_id = shift;

    unless (defined $value_id) {
        Carp::confess();
    }

    my $method_identifier = substr($value_id,0,2);
    $value_id = substr($value_id, 2, length($value_id)-2);    
    if ($method_identifier eq "F:") {
        return $self->value_id_to_values_frozen($value_id);
    }

    my @values = ($value_id =~ /(.*?)$record_sep/gs);
    for (@values) {
        if (substr($_,-1) eq $unit_sep) {
            #$_ = [split($unit_sep,$_)]
            my @values2 = /(.*?)$unit_sep/gs;
            $_ = \@values2;
            for (@values2) {
                if ($_ eq $null_value) {
                    $_ = undef;
                }
                elsif ($_ eq $empty_string) {
                    $_ = "";
                }
            }            
        }
        elsif ($_ eq $null_value) {
            $_ = undef;
        }
        elsif ($_ eq $empty_string) {
            $_ = "";
        }
        elsif ($_ eq $empty_list) {
            $_ = [];
        }
    }
    return @values;
}


1;
