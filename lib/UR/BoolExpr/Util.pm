
package UR::BoolExpr::Util;

# Non-OO Utility methods for the rule modules.

use strict;
use warnings;
require UR;
our $VERSION = "0.41"; # UR $VERSION;

use Scalar::Util qw(blessed reftype refaddr);
use Data::Dumper;
use FreezeThaw;

# Because the id is actually a full data structure we need some separators.
# Note that these are used for the common case, where FreezeThaw is for arbitrarily complicated rule identifiers.

our $id_sep = chr(29);          # spearetes id property values instead of the old \t
our $record_sep = chr(30);      # within a value_id, delimits a distinct values
our $unit_sep = chr(31);        # seperates items within a single value

our $null_value = chr(21);      # used for undef/null
our $empty_string = chr(28);    # used for ""
our $empty_list = chr(20);      # used for []

# These are used when there is any sort of complicated data in the rule.

sub values_to_value_id_frozen {
    my $self = shift;
    my $frozen = FreezeThaw::safeFreeze(@_);
    return "F:" . $frozen;
}

sub value_id_to_values_frozen {
    my $self = shift;
    my $value_id = shift;
    return $self->_fixup_ur_objects_from_thawed_data(FreezeThaw::thaw($value_id));
}

sub _fixup_ur_objects_from_thawed_data {
    my $self = shift;
    my @values = @_;

    our $seen;
    local $seen = $seen;
    $seen ||= {};

    # For things that are UR::Objects (or used to be UR objects), swap the
    # thawed/cloned one with one from the object cache
    #
    # This sub is localized inside _fixup_ur_objects_from_thawed_data so it's not called
    # externally, and uses $_ as the thing to process, which is set in the foreach loop
    # below - both as a performance speedup of# not having to prepare an argument list while
    # processing a possibly deep data structure, and clarity of avoiding double dereferencing
    # as this sub needs to mutate the item it's processing
    my $process_it = sub {
        if (blessed($_)
            and (
                $_->isa('UR::Object')
                or
                $_->isa('UR::BoolExpr::Util::clonedThing')
            )
        ) {
            my($class, $id) = ($_->class, $_->id);
            if (refaddr($_) != refaddr($UR::Context::all_objects_loaded->{$class}->{$id})) {
                # bless the original thing to a non-UR::Object class so UR::Object::DESTROY
                # doesn't run on it
                my $cloned_thing = UR::BoolExpr::Util::clonedThing->bless($_);
                # Swap in the object from the object cache
                $_ = $UR::Context::all_objects_loaded->{$class}->{$id};
            }

        }
        $self->_fixup_ur_objects_from_thawed_data($_);
    };

    foreach my $data ( @values ) {
        next unless ref $data; # Don't need to recursively inspect normal scalar data
        next if $seen->{$data}++;

        if (ref $data) {
            my $reftype = reftype($data);
            my $iter;
            if ($reftype eq 'ARRAY') {
                foreach (@$data) {
                    &$process_it;
                }
            } elsif ($reftype eq 'HASH') {
                foreach (values %$data) {
                    &$process_it;
                }

            } elsif ($reftype eq 'SCALAR' or $reftype eq 'REF') {
                local $_ = $$data;
                &$process_it;
            }
        }
    }
    return @values;
}

# These are used for the simple common-case rules.

sub values_to_value_id {
    my $self = shift;
    my $value_id = "O:";

    for my $value (@_) {

        no warnings;# 'uninitialized';
        if (length($value)) {
            if (ref($value) eq "ARRAY") {
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
                            if (ref($value2) or index($value2, $unit_sep) >= 0 or index($value2, $record_sep) >= 0) {
                                return $self->values_to_value_id_frozen(@_);
                            }
                            $value_id .= $value2 . $unit_sep;
                        }
                    }
                }
                $value_id .= $record_sep;
            }
            else {
                if (ref($value) or index($value,$unit_sep) >= 0 or index($value,$record_sep) >= 0) {
                    return $self->values_to_value_id_frozen(@_);
                }
                $value_id .= $value . $record_sep;
            }
        } elsif (not defined $value ) {
            $value_id .= $null_value . $record_sep;
        }
        else {# ($value eq "") {
            $value_id .= $empty_string . $record_sep;
        }
    }
    return $value_id;
}

sub value_id_to_values {
    my $self = shift;
    my $value_id = shift;

    unless (defined $value_id) {
        Carp::confess('No value_id passed in to value_id_to_values()!?');
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

*values_to_value_id_simple = \&values_to_value_id;

package UR::BoolExpr::Util::clonedThing;

sub bless {
    my($class, $thing) = @_;
#    return $thing if ($thing->isa(__PACKAGE__));

    $thing->{__original_class} = $thing->class;
    bless $thing, $class;
}

sub id {
    return shift->{id};
}

sub class {
    return shift->{__original_class};
}

1;

=pod

=head1 NAME

UR::BoolExpr::Util - non-OO module to collect utility functions used by the BoolExpr modules

=cut

