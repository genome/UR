package UR::DataSource::Filesystem;

use UR;
use strict;
use warnings;
our $VERSION = "0.37"; # UR $VERSION;

use File::Basename;
use List::Util;


# lets you specify the server in several ways:
# server => '/path/name'
#    means there is one file storing the data
# server => [ '/path1/name', '/path2/name' ]
#    means the first tile we need to open the file, pick one (for load balancing)
# server => '/path/to/directory/'
#    means that directory contains one or more files, and the classes using
#    this datasource can have table_name metadata to pick the file
# server => '/path/$param1/${param2}.ext'
#    means the values for $param1 and $param2 should come from the input rule.
#    If the rule doesn't specify the param, then it should glob for the possible
#    names at that point in the filesystem
# server => '/path/&method/filename'
#    means the value for that part of the path should come from a method call
#    run as $subject_class_name->$method($rule)
# server => '/path/*/path/$name/
#    means it should glob at the appropriate time for the '*', but no use the
#    paths found matching the glob to infer any values

              

class UR::DataSource::Filesystem {
    is => 'UR::DataSource',
    has => [
        server                => { doc => 'Path spec for the path on the filesystem containing the data' },
        delimiter             => { is => 'String', default_value => '\s*,\s*', doc => 'Delimiter between columns on the same line' },
        record_separator      => { is => 'String', default_value => "\n", doc => 'Delimiter between lines in the file' },
        header_lines          => { is => 'Integer', default_value => 0, doc => 'Number of lines at the start of the file to skip' },
        columns_from_header   => { is => 'Boolean', default_value => 0, doc => 'The column names are in the first line of the file' },
        handle_class          => { is => 'String', default_value => 'IO::File', doc => 'Class to use for new file handles' },
        quick_disconnect      => { is => 'Boolean', default_value => 1, doc => 'Do not hold the file handle open between requests' },
    ],
    has_optional => [
        columns               => { is => 'ARRAY', doc => 'Names of the columns in the file, in order' },
        sort_order            => { is => 'ARRAY', doc => 'Names of the columns by which the data file is sorted' },
    ],
    doc => 'A data source for treating files as relational data',
};

sub can_savepoint { 0;}  # Doesn't support savepoints


sub _logger {
    my $self = shift;
    my $varname = shift;
    if ($ENV{$varname}) {
        my $log_fh = UR::DBI->sql_fh;
        return sub { 
                   my $msg = shift;
                   my $time = time();
                   $msg =~ s/\b\$time\b/$time/g;
                   my $localtime = scalar(localtime $time);
                   $msg =~ s/\b\$localtime\b/$localtime/;

                   $log_fh->print($msg);
               };
    } else {
        return sub {1;};
    }
}


sub _replace_vars_with_values_in_pathname {
    my($self, $rule, $string, $prop_values_hash) = @_;

    $prop_values_hash ||= {};

    # Match something like /some/path/$var/name or /some/path${var}.ext/name
    if ($string =~ m/\$\{?(\w+)\}?/) {
        my $varname = $1;
        my $subject_class_name = $rule->subject_class_name;
        unless ($subject_class_name->__meta__->property_meta_for_name($varname)) {
            Carp::croak("Invalid 'server' for data source ".$self->id
                        . ": Path spec $string requires a value for property $varname "
                        . " which is not a property of class $subject_class_name");
        }
        my @string_replacement_values;

        if ($rule->specifies_value_for($varname)) {
            my @property_values = $rule->value_for($varname);
            if (@property_values == 1 and ref($property_values[0]) eq 'ARRAY') {
                @property_values = @{$property_values[0]};
            }
            # Make a listref that has one element per value for that property in the rule (in-clause
            # rules may have more than one value)
            # Each element has 2 parts, first is the value, second is the accumulated prop_values_hash
            # where we've added the occurance of this property havine one of the values
            @property_values = map { [ $_, { %$prop_values_hash, $varname => $_ } ] } @property_values;

            # Escape any shell glob characters in the values: [ ] { } ~ ? * and \
            # we don't want a property with value '?' to be a glob wildcard
            @string_replacement_values = map { $_->[0] =~ s/([[\]{}~?*\\])/\\$1/; $_ } @property_values;

        } else {
            # The rule doesn't have a value for this property.
            # Put a shell wildcard in here, and a later glob will match things
            my @glob_positions = @{ $prop_values_hash->{'.__glob_positions__'} || [] };

            # Here, the string position as a key means that the * in this position should
            # later be expanded to fill in values for this variable.  That's ok since numbers
            # can't be property names
            my $glob_pos = $-[0];
            push @glob_positions, [$glob_pos, $varname];
            @string_replacement_values = ([ '*', { %$prop_values_hash, '.__glob_positions__' => \@glob_positions} ]);
        }

        my @return = map {
                         my $s = $string;
                         substr($s, $-[0], $+[0] - $-[0], $_->[0]);
                         [ $s, $_->[1] ];
                     }
                     @string_replacement_values;
        return map { $self->_replace_vars_with_values_in_pathname($rule, @$_) } @return;

    } else {
        return [ $string, $prop_values_hash ];
    }
}

sub _replace_subs_with_values_in_pathname {
    my($self, $rule, $string, $prop_values_hash) = @_;

    $prop_values_hash ||= {};

    # Match something like /some/path/&sub/name or /some/path&{sub}.ext/name
    if ($string =~ m/\&\{?(\w+)\}?/) {
        my $subname = $1;
        unless ($rule->subject_class->can($subname)) {
            Carp::croak("Invalid 'server' for data source ".$self->id
                        . ": Path spec $string requires a value for method $subname "
                        . " which is not a method of class " . $rule->subject_class_name);
        }
 
        my $subject_class_name = $rule->subject_class_name;
        my @property_values = { $subject_class_name->$subname($rule) };
        if ($@) {
            Carp::croak("Can't resolve final path for 'server' for data source ".$self->id
                        . ": Method call to ${subject_class_name}::${subname} died with: $@");
        }
        if (@property_values == 1 and ref($property_values[0]) eq 'ARRAY') {
            @property_values = @{$property_values[0]};
        }
        # Make a listref that has one element per value for that property in the rule (in-clause
        # rules may have more than one value)
        # Each element has 2 parts, first is the value, second is the accumulated prop_values_hash
        # where we've added the occurance of this property havine one of the values
        # FIXME - do we need a copy of $prop_values_hash, or is the same ref good enough
        @property_values = map { [ $_, { %$prop_values_hash } ] } @property_values;

        # Escape any shell glob characters in the values: [ ] { } ~ ? * and \
        # we don't want a property with value '?' to be a glob wildcard
        my @string_replacement_values = map { $_->[0] =~ s/([[\]{}~?*\\])/\\$1/ } @property_values;

        my @return = map {
                         my $s = $string;
                         substr($s, $-[0], $+[0] - $-[0], $_->[0]);
                         [ $s, $_->[1] ];
                     }
                     @string_replacement_values;
        return map { $self->_replace_subs_with_values_in_pathname($rule, @$_) } @return;

    } else {
        return [ $string, $prop_values_hash ];
    }
}

sub _replace_glob_with_values_in_pathname {
    my($self, $string, $prop_values_hash) = @_;

$DB::single=1;
    # a * not preceeded by a backslash, delimited by /
    if ($string =~ m#([^/]*[^\\/]?(\*)[^/]*)#) {
        my $glob_pos = $-[2];

        my $path_segment_including_glob = substr($string, 0, $+[0]);
        my $remaining_path = substr($string, $+[0]);
        my @glob_matches = map { $_ . $remaining_path }
                               glob($path_segment_including_glob);

        my @property_values_as_hashes;
        my $glob_position_list = $prop_values_hash->{'.__glob_positions__'};
        if ($glob_position_list->[0]->[0] == $glob_pos) {
            # This * was put in previously by a $propname in the spec that wasn't mentioned in the rule

            my $path_delim_pos = index($path_segment_including_glob, '/', $glob_pos);
            $path_delim_pos = length($path_segment_including_glob) if ($path_delim_pos == -1);  # No more /s

            #my $regex_as_str = quotemeta($path_segment_including_glob);
            my $regex_as_str = $path_segment_including_glob;
            # Find out just how many *s we're dealing with, up to the next /
            my(@glob_positions, @property_names);
            while (@$glob_position_list
                   and
                  $glob_position_list->[0]->[0] < $path_delim_pos
            ) {
                my $this_glob_info = shift @{$glob_position_list};
                push @glob_positions, $this_glob_info->[0];
                push @property_names, $this_glob_info->[1];
            }
            # Replace the *s found with regex captures
            my $glob_replacement = '([^/]*)';
            my $glob_rpl_offset = 0;
            my $offset_inc = length($glob_replacement) - 1;
            #for(my $i = 0; $i < @glob_positions; $i++) {
            #    substr($regex_as_str, $glob_positions[$i], 1, $glob_replacement);
            #    $glob_rpl_offset += $glob_rpl_offset;
            #}
            $regex_as_str = List::Util::reduce( sub {
                                                    substr($a, $b + $glob_rpl_offset, 1, $glob_replacement);
                                                    $glob_rpl_offset += $offset_inc;
                                                    $a;
                                                },
                                                ($regex_as_str, @glob_positions) );

            my $regex = qr{$regex_as_str};

            my @property_values_for_each_glob_match = map { [ $_, [ $_ =~ $regex] ] } @glob_matches;
            @property_values_as_hashes = map { my %h = %$prop_values_hash;
                                               @h{@property_names} = @{$_->[1]};
                                               [$_->[0], \%h];
                                             }
                                             @property_values_for_each_glob_match;

       } else {
           # This is a glob put in the original path spec

           my $original_path_length = length($string);

           # Given a pathname returned from the glob, return a new glob_position_list
           # that has fixed up the position information accounting for the fact that
           # the globbed pathname is a different length than the original spec
           my $apply_fixups_for_glob_list = sub {
                  my $glob_match = shift;
                  return map { [ $_->[0] + length($glob_match) - $original_path_length, $_->[1] ] } @$glob_position_list;
           };

           @property_values_as_hashes = map { [
                                                $_,
                                                { %$prop_values_hash,
                                                  '.__glob_positions__' => [ $apply_fixups_for_glob_list->($_) ]
                                                }
                                              ]
                                            }
                                            @glob_matches;
       }

       return map { $self->_replace_glob_with_values_in_pathname( @$_ ) }
                  @property_values_as_hashes;

    } else {
        delete $prop_values_hash->{'.__glob_positions__'};
        return [ $string, $prop_values_hash ];
    }
}

1;
