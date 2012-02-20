package UR::DataSource::Filesystem;

use UR;
use strict;
use warnings;
our $VERSION = "0.37"; # UR $VERSION;

use File::Basename;
use List::Util;
use Scalar::Util;
use Errno qw(EINTR EAGAIN EOPNOTSUPP);

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

# maybe suppert a URI scheme like
# file:/path/$to/File.ext?columns=[a,b,c]&sorted_columns=[a,b]

# TODO
# * Need to handle the case where the file data is not sorted in ID order
# * Change the comparator functions to accept a ref to the file's value to avoid
#   copying large strings
# * Support non-equality operators for properties that are part of the path spec


class UR::DataSource::Filesystem {
    is => 'UR::DataSource',
    has => [
        path                  => { doc => 'Path spec for the path on the filesystem containing the data' },
        delimiter             => { is => 'String', default_value => '\s*,\s*', doc => 'Delimiter between columns on the same line' },
        record_separator      => { is => 'String', default_value => "\n", doc => 'Delimiter between lines in the file' },
        header_lines          => { is => 'Integer', default_value => 0, doc => 'Number of lines at the start of the file to skip' },
        columns_from_header   => { is => 'Boolean', default_value => 0, doc => 'The column names are in the first line of the file' },
        handle_class          => { is => 'String', default_value => 'IO::File', doc => 'Class to use for new file handles' },
        quick_disconnect      => { is => 'Boolean', default_value => 1, doc => 'Do not hold the file handle open between requests' },
    ],
    has_optional => [
        columns               => { is => 'ARRAY', doc => 'Names of the columns in the file, in order' },
        sorted_columns        => { is => 'ARRAY', doc => 'Names of the columns by which the data file is sorted' },
    ],
    doc => 'A data source for treating files as relational data',
};

sub can_savepoint { 0;}  # Doesn't support savepoints

sub _regex {
    my $self = shift;

    unless ($self->{'_regex'}) {
        my $delimiter = $self->delimiter;
        my $r = eval { qr($delimiter)  };
        if ($@ || !$r) {
            $self->error_message("Unable to interepret delimiter '".$self->delimiter.": $@");
            return;
        }
        $self->{'_regex'} = $r;
    }
    return $self->{'_regex'};
}


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
        return \&UR::Util::null_sub;
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
            # The '.__glob_positions__' key holds a list of places we've inserted shell globs.
            # Each element is a 2-element list: index 0 is the string position, element 1 if the variable name.
            # This is needed so the later glob expansion can tell the difference between globs
            # that are part of the original path spec, and globs put in here
            my @glob_positions = @{ $prop_values_hash->{'.__glob_positions__'} || [] };

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

        # recursion to process the next variable replacement
        return map { $self->_replace_vars_with_values_in_pathname($rule, @$_) } @return;

    } else {
        return [ $string, $prop_values_hash ];
    }
}

sub _replace_subs_with_values_in_pathname {
    my($self, $rule, $string, $prop_values_hash) = @_;

    $prop_values_hash ||= {};
    my $subject_class_name = $rule->subject_class_name;

    # Match something like /some/path/&sub/name or /some/path&{sub}.ext/name
    if ($string =~ m/\&\{?(\w+)\}?/) {
        my $subname = $1;
        unless ($subject_class_name->can($subname)) {
            Carp::croak("Invalid 'server' for data source ".$self->id
                        . ": Path spec $string requires a value for method $subname "
                        . " which is not a method of class " . $rule->subject_class_name);
        }
 
        my @property_values = eval { $subject_class_name->$subname($rule) };
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
        @property_values = map { [ $_, { %$prop_values_hash } ] } @property_values;

        # Escape any shell glob characters in the values: [ ] { } ~ ? * and \
        # we don't want a return value '?' or '*' to be a glob wildcard
        my @string_replacement_values = map { $_->[0] =~ s/([[\]{}~?*\\])/\\$1/; $_ } @property_values;

        # Given a pathname returned from the glob, return a new glob_position_list
        # that has fixed up the position information accounting for the fact that
        # the globbed pathname is a different length than the original spec
        my $original_path_length = length($string);
        my $glob_position_list = $prop_values_hash->{'.__glob_positions__'};
        my $subname_replacement_position = $-[0];
        my $fix_offsets_in_glob_list = sub {
               my $pathname = shift;
               # alter the position only if it is greater than the position of
               # the subname we're replacing
               return map { [ $_->[0] < $subname_replacement_position
                                  ? $_->[0]
                                  : $_->[0] + length($pathname) - $original_path_length,
                             $_->[1] ]
                          }
                          @$glob_position_list;
        };

        my @return = map {
                         my $s = $string;
                         substr($s, $-[0], $+[0] - $-[0], $_->[0]);
                         $_->[1]->{'.__glob_positions__'} = [ $fix_offsets_in_glob_list->($s) ];
                         [ $s, $_->[1] ];
                     }
                     @string_replacement_values;

        # recursion to process the next method call
        return map { $self->_replace_subs_with_values_in_pathname($rule, @$_) } @return;

    } else {
        return [ $string, $prop_values_hash ];
    }
}

sub _replace_glob_with_values_in_pathname {
    my($self, $string, $prop_values_hash) = @_;

    # a * not preceeded by a backslash, delimited by /
    if ($string =~ m#([^/]*?[^\\/]?(\*)[^/]*)#) {
        my $glob_pos = $-[2];

        my $path_segment_including_glob = substr($string, 0, $+[0]);
        my $remaining_path = substr($string, $+[0]);
        my @glob_matches = map { $_ . $remaining_path }
                               glob($path_segment_including_glob);

        my $resolve_glob_values_for_each_result;
        my $glob_position_list = $prop_values_hash->{'.__glob_positions__'};

        # Given a pathname returned from the glob, return a new glob_position_list
        # that has fixed up the position information accounting for the fact that
        # the globbed pathname is a different length than the original spec
        my $original_path_length = length($string);
        my $fix_offsets_in_glob_list = sub {
               my $pathname = shift;
               return map { [ $_->[0] + length($pathname) - $original_path_length, $_->[1] ] } @$glob_position_list;
        };

        if ($glob_position_list->[0]->[0] == $glob_pos) {
            # This * was put in previously by a $propname in the spec that wasn't mentioned in the rule

            my $path_delim_pos = index($path_segment_including_glob, '/', $glob_pos);
            $path_delim_pos = length($path_segment_including_glob) if ($path_delim_pos == -1);  # No more /s

            my $regex_as_str = $path_segment_including_glob;
            # Find out just how many *s we're dealing with and where they are, up to the next /
            # remove them from the glob_position_list because we're going to resolve their values
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
            my $offset_inc = length($glob_replacement) - 1;  # replacing a 1-char string '*' with a 7-char string '([^/]*)'
            $regex_as_str = List::Util::reduce( sub {
                                                    substr($a, $b + $glob_rpl_offset, 1, $glob_replacement);
                                                    $glob_rpl_offset += $offset_inc;
                                                    $a;
                                                },
                                                ($regex_as_str, @glob_positions) );

            my $regex = qr{$regex_as_str};
            my @property_values_for_each_glob_match = map { [ $_, [ $_ =~ $regex] ] } @glob_matches;

            # Fill in the property names into .__glob_positions__
            # we've resolved in this iteration, and apply offset fixups for the
            # difference in string length between the pre- and post-glob pathnames

            $resolve_glob_values_for_each_result = sub {
                return map {
                               my %h = %$prop_values_hash;
                               @h{@property_names} = @{$_->[1]};
                               $h{'.__glob_positions__'} = [ $fix_offsets_in_glob_list->($_->[0]) ];
                               [$_->[0], \%h];
                           }
                           @property_values_for_each_glob_match;
            };

       } else {
           # This is a glob put in the original path spec
           # The new path comes from the @glob_matches list.
           # Apply offset fixups for the difference in string length between the
           # pre- and post-glob pathnames
           $resolve_glob_values_for_each_result = sub {
               return map { [
                                $_,
                                { %$prop_values_hash,
                                  '.__glob_positions__' => [ $fix_offsets_in_glob_list->($_) ]
                                }
                            ]
                          }
                          @glob_matches;
           };
       }

       my @resolved_paths_and_property_values = $resolve_glob_values_for_each_result->();

       # Recursion to process the next glob
       return map { $self->_replace_glob_with_values_in_pathname( @$_ ) }
                  @resolved_paths_and_property_values;

    } else {
        delete $prop_values_hash->{'.__glob_positions__'};
        return [ $string, $prop_values_hash ];
    }
}


sub resolve_file_info_for_rule_and_path_spec {
    my($self, $rule, $path_spec) = @_;

    $path_spec ||= $self->path;

    return map { $self->_replace_glob_with_values_in_pathname(@$_) }
           map { $self->_replace_subs_with_values_in_pathname($rule, @$_) }
               $self->_replace_vars_with_values_in_pathname($rule, $path_spec);
}



# Names of creation params that we should force to be listrefs
our %creation_param_is_list = map { $_ => 1 } qw( columns sorted_columns );
sub create_from_inline_class_data {
    my($class, $class_data, $ds_data) = @_;

    #unless (exists $ds_data->{'columns'}) {
        # User didn't specify columns in the file.  Assumme every property is a column, and in the same order
        # We'll have to ask the class object for the column list the first time there's a query
    #}

    my %ds_creation_params;
    foreach my $param ( qw( path delimiter record_separator columns header_lines
                            columns_from_header handle_class quick_disconnect sorted_columns )
    ) {
        if (exists $ds_data->{$param}) {
            if ($creation_param_is_list{$param} and ref($ds_data->{$param}) ne 'ARRAY') {
                $ds_creation_params{$param} = \( $ds_data->{$param} );
            } else {
                $ds_creation_params{$param} = $ds_data->{$param};
            }
        }
    }

    my $ds_id = UR::Object::Type->autogenerate_new_object_id_uuid();
    my $ds_type = delete $ds_data->{'is'} || __PACKAGE__;
    my $ds = $ds_type->create( %ds_creation_params, id => $ds_id );
    return $ds;
}



sub _things_in_list_are_numeric {
    my $self = shift;

    foreach ( @{$_[0]} ) {
        return 0 if (! Scalar::Util::looks_like_number($_));
    }
    return 1;
}

# Construct a closure to perform an operator test against the given value
# The closures return 0 is the test is successful, -1 if unsuccessful but
# the file's value was less than $value, and 1 if unsuccessful and greater.
# The iterator that churns through the file knows that if it's comparing an
# ID/sorted column, and the comparator returns 1 then we've gone past the
# point where we can expect to ever find another successful match and we
# should stop looking
my $ALWAYS_FALSE = sub { -1 };
sub _comparator_for_operator_and_property {
    my($self,$property,$operator,$value) = @_;

    no warnings 'uninitialized';  # we're handling ''/undef/null specially below where it matters

    if ($operator eq 'between') {
        if ($value->[0] eq '' or $value->[1] eq '') {
            return $ALWAYS_FALSE;
        }

        if ($property->is_numeric and $self->_things_in_list_are_numeric($value)) {
            if ($value->[0] > $value->[1]) {
                # Will never be true
                Carp::carp "'between' comparison will never be true with values ".$value->[0]," and ".$value->[1];
                return $ALWAYS_FALSE;
            }

            # numeric 'between' comparison
            return sub {
                       return -1 if ($_[0] eq '');
                       if ($_[0] < $value->[0]) {
                           return -1;
                       } elsif ($_[0] > $value->[1]) {
                           return 1;
                       } else {
                           return 0;
                       }
                   };
        } else {
            if ($value->[0] gt $value->[1]) {
                Carp::carp "'between' comparison will never be true with values ".$value->[0]," and ".$value->[1];
                return $ALWAYS_FALSE;
            }

            # A string 'between' comparison
            return sub {
                       return -1 if ($_[0] eq '');
                       if ($_[0] lt $value->[0]) {
                           return -1;
                       } elsif ($_[0] gt $value->[1]) {
                           return 1;
                       } else {
                           return 0;
                       }
                   };
        }

    } elsif ($operator eq 'in') {
        if (! @$value) {
            return $ALWAYS_FALSE;
        }

        if ($property->is_numeric and $self->_things_in_list_are_numeric($value)) {
            # Numeric 'in' comparison  returns undef if we're within the range of the list
            # but don't actually match any of the items in the list
            @$value = sort { $a <=> $b } @$value;  # sort the values first
            return sub {
                       return -1 if ($_[0] eq '');
                       if ($_[0] < $value->[0]) {
                           return -1;
                       } elsif ($_[0] > $value->[-1]) {
                           return 1;
                       } else {
                           foreach ( @$value ) {
                               return 0 if $_[0] == $_;
                           }
                           return -1;
                       }
                   };

        } else {
            # A string 'in' comparison
            @$value = sort { $a cmp $b } @$value;
            return sub {
                       if ($_[0] lt $value->[0]) {
                           return -1;
                       } elsif ($_[0] gt $value->[-1]) {
                           return 1;
                       } else {
                           foreach ( @$value ) {
                               return 0 if $_[0] eq $_;
                           }
                           return -1;
                       }
                   };

        }

    } elsif ($operator eq 'not in') {
        if (! @$value) {
            return $ALWAYS_FALSE;
        }

        if ($property->is_numeric and $self->_things_in_list_are_numeric($value)) {
            return sub {
                return -1 if ($_[0] eq '');
                foreach ( @$value ) {
                    return -1 if $_[0] == $_;
                }
                return 0;
            }

        } else {
            return sub {
                foreach ( @$value ) {
                    return -1 if $_[0] eq $_;
                }
                return 0;
            }
        }

    } elsif ($operator eq 'like') {
        # 'like' is always a string comparison.  In addition, we can't know if we're ahead
        # or behind in the file's ID columns, so the only two return values are 0 and 1

        return $ALWAYS_FALSE if ($value eq '');  # property like NULL is always false

        # Convert SQL-type wildcards to Perl-type wildcards
        # Convert a % to a *, and _ to ., unless they're preceeded by \ to escape them.
        # Not that this isn't precisely correct, as \\% should really mean a literal \
        # followed by a wildcard, but we can't be correct in all cases without including 
        # a real parser.  This will catch most cases.

        $value =~ s/(?<!\\)%/.*/g;
        $value =~ s/(?<!\\)_/./g;
        my $regex = qr($value);
        return sub {
                   return -1 if ($_[0] eq '');
                   if ($_[0] =~ $regex) {
                       return 0;
                   } else {
                       return 1;
                   }
               };

    } elsif ($operator eq 'not like') {
        return $ALWAYS_FALSE if ($value eq '');  # property like NULL is always false
        $value =~ s/(?<!\\)%/.*/;
        $value =~ s/(?<!\\)_/./;
        my $regex = qr($value);
        return sub {
                   return -1 if ($_[0] eq '');
                   if ($_[0] =~ $regex) {
                       return 1;
                   } else {
                       return 0;
                   }
               };


    # FIXME - should we only be testing the numericness of the property?
    } elsif ($property->is_numeric and $self->_things_in_list_are_numeric([$value])) {
        # Basic numeric comparisons
        if ($operator eq '=') {
            return sub {
                       return -1 if ($_[0] eq ''); # null always != a number
                       return $_[0] <=> $value;
                   };
        } elsif ($operator eq '<') {
            return sub {
                       return -1 if ($_[0] eq ''); # null always != a number
                       $_[0] < $value ? 0 : 1;
                   };
        } elsif ($operator eq '<=') {
            return sub {
                       return -1 if ($_[0] eq ''); # null always != a number
                       $_[0] <= $value ? 0 : 1;
                   };
        } elsif ($operator eq '>') {
            return sub {
                       return -1 if ($_[0] eq ''); # null always != a number
                       $_[0] > $value ? 0 : -1;
                   };
        } elsif ($operator eq '>=') {
            return sub {
                       return -1 if ($_[0] eq ''); # null always != a number
                       $_[0] >= $value ? 0 : -1;
                   };
        } elsif ($operator eq 'true') {
            return sub {
                       $_[0] ? 0 : -1;
                   };
        } elsif ($operator eq 'false') {
            return sub {
                       $_[0] ? -1 : 0;
                   };
        } elsif ($operator eq '!=' or $operator eq 'ne') {
             return sub {
                       return 0 if ($_[0] eq '');  # null always != a number
                       $_[0] != $value ? 0 : -1;
             }
        }

    } else {
        # Basic string comparisons
        if ($operator eq '=') {
            return sub {
                       return -1 if ($_[0] eq '' xor $value eq '');
                       return $_[0] cmp $value;
                   };
        } elsif ($operator eq '<') {
            return sub {
                       $_[0] lt $value ? 0 : 1;
                   };
        } elsif ($operator eq '<=') {
            return sub {
                       return -1 if ($_[0] eq '' or $value eq '');
                       $_[0] le $value ? 0 : 1;
                   };
        } elsif ($operator eq '>') {
            return sub {
                       $_[0] gt $value ? 0 : -1;
                   };
        } elsif ($operator eq '>=') {
            return sub {
                       return -1 if ($_[0] eq '' or $value eq '');
                       $_[0] ge $value ? 0 : -1;
                   };
        } elsif ($operator eq 'true') {
            return sub {
                       $_[0] ? 0 : -1;
                   };
        } elsif ($operator eq 'false') {
            return sub {
                       $_[0] ? -1 : 0;
                   };
        } elsif ($operator eq '!=' or $operator eq 'ne') {
             return sub {
                       $_[0] ne $value ? 0 : -1;
             }
        }
    }
}



sub _properties_from_path_spec {
    my($self) = @_;

    unless (exists $self->{'__properties_from_path_spec'}) {
        my $path = $self->path;
        $path = $path->[0] if ref($path);

        my @property_names;
        while($path =~ m/\G\$\{?(\w+)\}?/) {
            push @property_names, $1;
        }
        $self->{'__properties_from_path_spec'} = \@property_names;
    }
    return @{ $self->{'__properties_from_path_spec'} };
}


sub _generate_loading_templates_arrayref {
    my($self, $old_sql_cols) = @_;

    # Each elt in @$column_data is a quad:
    # [ $class_meta, $property_meta, $table_name, $object_num ]
    # Keep only the properties with columns (mostly just to remove UR::Object::id
    my @sql_cols = grep { $_->[1]->column_name }
                        @$old_sql_cols;

    my $template_data = $self->SUPER::_generate_loading_templates_arrayref(\@sql_cols);
    return $template_data;
}



sub create_iterator_closure_for_rule {
    my($self,$rule) = @_;

    my $class_name = $rule->subject_class_name;
    my $class_meta = $class_name->__meta__;
    my $rule_template = $rule->template;

$DB::single=1;
    my $column_names_in_order = $self->columns;
    my $column_name_count = 0;
    my %column_name_to_index_map = map { $column_names_in_order->[$column_name_count] => $column_name_count++ }
                                       @$column_names_in_order;

    my $sorted_column_names = $self->sorted_columns || [];
    my %sorted_column_names = map { $_ => 1 } @$sorted_column_names;
    my @unsorted_column_names = grep { ! exists $sorted_column_names{$_} } @$column_names_in_order;

    my %property_name_to_index_map;
    for (my $i = 0; $i < $column_name_count; $i++) {
        my $column_name = $column_names_in_order->[$i];
        my $property_name = $class_meta->property_for_column($column_name);
        $property_name_to_index_map{$property_name} = $i;
    }

    my @rule_columns_in_order;         # The order we should perform rule matches on - value is the index in the file row to test
    my @comparison_for_column;         # closures to call to perform the match - same order as @rule_columns_in_order

    my(%property_for_column, %operator_for_column, %value_for_column); # These are used for logging

    my $resolve_comparator_for_column = sub {
        my $column_name = shift;

        my $property_name = $class_meta->property_for_column($column_name);
        return unless $rule->specifies_value_for($property_name);

        my $operator = $rule->operator_for($property_name)
                     || '=';
        my $rule_value = $rule->value_for($property_name);

        $property_for_column{$column_name} = $property_name;
        $operator_for_column{$column_name} = $operator;
        $value_for_column{$column_name}    = $rule_value;

        my $comp_function = $self->_comparator_for_operator_and_property(
                                   $class_meta->property($property_name),
                                   $operator,
                                   $rule_value);

        push @rule_columns_in_order, $column_name_to_index_map{$column_name};
        push @comparison_for_column, $comp_function;
        return 1;
    };

    my $sorted_columns_in_rule_count = 0;  # How many columns we can consider when trying "the shortcut" for sorted data
    my %column_is_used_in_sorted_capacity;
    foreach my $column_name ( @$sorted_column_names ) {
        if (! $resolve_comparator_for_column->($column_name)
              and ! defined($sorted_columns_in_rule_count)
        ) {
            # The fiest time we don't match a sorted column, record the index
            $sorted_columns_in_rule_count = scalar(@rule_columns_in_order)
        } else {
            $column_is_used_in_sorted_capacity{$column_name} = ' (sorted)';
        }
    }

    foreach my $column_name ( @unsorted_column_names ) {
        $resolve_comparator_for_column->($column_name);
    }

    my @possible_file_info_list = $self->resolve_file_info_for_rule_and_path_spec($rule);

    if (my $table_name = $class_meta->table_name) {
        # Tack the final file name onto the end if the class has a table name
        @possible_file_info_list = map { [ $_->[0] . "/$table_name", $_->[1] ] } @possible_file_info_list;
    }

    my $handle_class = $self->handle_class;
    my $use_quick_read = $handle_class->isa('IO::Handle');
    my $split_regex = $self->_regex();
    my $logger = $self->_logger('UR_DBI_MONITOR_SQL');
    my $record_separator = $self->record_separator;

    my $monitor_start_time = Time::HiRes::time();

    { no warnings 'uninitialized';
      $logger->("\nFILE: starting query covering " . scalar(@possible_file_info_list)." files:\n\t"
                . join("\n\t", map { $_->[0] } @possible_file_info_list )
                . "\nFILTERS: "
                . join("\n\t", map {
                                     $_ . " [$column_name_to_index_map{$_}]"
                                        .  $column_is_used_in_sorted_capacity{$_}
                                        . " $operator_for_column{$_} "
                                        . (ref($value_for_column{$_}) eq 'ARRAY'
                                                                     ? '[' . join(',',@{$value_for_column{$_}}) .']'
                                                                     : $value_for_column{$_} )
                                   }
                               map { $column_names_in_order->[$_] }
                               @rule_columns_in_order)
                . "\n\n"
              );
    }

    my $query_plan = $self->_resolve_query_plan($rule_template);
    if (@{ $query_plan->{'loading_templates'} } > 1) {
        Carp::croak(__PACKAGE__ . " does not support joins.  The rule was $rule");
    }
    my $loading_template = $query_plan->{loading_templates}->[0];
    my @property_names_in_loading_template_order = @{ $loading_template->{'property_names'} };

    my @iterator_for_each_file;
    my @next_record_for_each_file;
    foreach ( @possible_file_info_list ) {
        my $pathname = $_->[0];
        my $property_values_from_path_spec = $_->[1];

        my @properties_from_path_spec = keys %$property_values_from_path_spec;
        my @values_from_path_spec     = values %$property_values_from_path_spec;

        my $fh = $handle_class->new($pathname);
        unless ($fh) {
            $logger->("FILE: Skipping $pathname because it did not open: $!\n");
            next;   # missing or unopenable files is not fatal
        }

        my $lines_read = 0;
        my $lines_matched = 0;

        my $log_first_fetch;
        $log_first_fetch = sub {
               $logger->(sprintf("FILE: $pathname FIRST FETCH TIME:  %.4f s\n\n", Time::HiRes::time() - $monitor_start_time));
               $log_first_fetch = \&UR::Util::null_sub;
           };
        my $log_first_match;
        $log_first_match = sub {
               $logger->("FILE: $pathname First match after reading $lines_read lines\n\n");
               $log_first_fetch = \&UR::Util::null_sub;
           };


        # How to transform the data read from the file/path-spec into the
        # list expected by the object fabricator.  A ref to a number means get the value from that
        # column of $next_record.  A regular value means copy that value directly (it came from the
        # path spec
        my @file_to_resultset_xform
            = map {
                  exists($property_values_from_path_spec->{$_})
                      ? $property_values_from_path_spec->{$_}
                      : \$property_name_to_index_map{$_};
             }
             @property_names_in_loading_template_order;

        my $next_record;

        my $read_record_from_file = sub {

            # Make sure some wise guy hasn't changed this out from under us
            local $/ = $record_separator;

            my $line;
            READ_LINE_FROM_FILE:
            while(! defined($line)) {
                # Hack for OSX 10.5.
                # At EOF, the getline below will return undef.  Most builds of Perl
                # will also set $! to 0 at EOF so you can distinguish between the cases
                # of EOF (which may have actually happened a while ago because of buffering)
                # and an actual read error.  OSX 10.5's Perl does not, and so $!
                # retains whatever value it had after the last failed syscall, likely 
                # a stat() while looking for a Perl module.  This should have no effect
                # other platforms where you can't trust $! at arbitrary points in time
                # anyway
                $! = 0;
                $line = $use_quick_read ? <$fh> : $fh->getline();

                unless (defined $line) {
                    if ($!) {
                        redo READ_LINE_FROM_FILE if ($! == EAGAIN or $! == EINTR);
                        Carp::croak("read failed for file $pathname: $!");
                    }

                    # at EOF.  Close up shop and remove this fh from the list
                    #flock($fh,LOCK_UN);
                    $fh = undef;
                    $next_record = undef;

                    $logger->("FILE: $pathname at EOF\n"
                              . "FILE: $lines_read lines read for this request.  $lines_matched matches in this file\n"
                              . sprintf("FILE: TOTAL EXECUTE-FETCH TIME: %.4f s\n\n", Time::HiRes::time() - $monitor_start_time)
                            );
                    return;
                }
            }
            $lines_read++;

            $line =~ s/$record_separator$//;  # chomp, but for any value
            # FIXME - to support record-oriented files, we need some replacement for this...
            $next_record = [ split($split_regex, $line, $column_name_count) ];
        };

        my $iterator_this_file;
        $iterator_this_file = sub {
            $log_first_fetch->();

            FOR_EACH_LINE:
            for(1) {
                $read_record_from_file->();

                unless ($next_record) {
                    # Done reading from this file
                    $iterator_this_file = \&UR::Util::null_sub;
                    return;
                }

                for (my $i = 0; $i < @comparison_for_column; $i++) {
                    my $comparison = $comparison_for_column[$i]->($next_record->[$rule_columns_in_order[$i]]);

                    if ($comparison > 0 and $i < $sorted_columns_in_rule_count) {
                        # We've gone past the last thing that could possibly match
                        $logger->("FILE: $pathname $lines_read lines read for this request.  $lines_matched matches\n"
                                  . sprintf("FILE: TOTAL EXECUTE-FETCH TIME: %.4f s\n", Time::HiRes::time() - $monitor_start_time));

                        #flock($fh,LOCK_UN);
                        return;

                    } elsif ($comparison) {
                        # comparison didn't match, read another line from the file
                        redo FOR_EACH_LINE;
                    }

                    # That comparison worked... stay in the for() loop for other comparisons
                }
            }
            # All the comparisons return '0', meaning they passed

            $log_first_match->();
            $lines_matched++;
            my @resultset = map { ref($_) ? $next_record->[$$_] : $_ } @file_to_resultset_xform;
            return \@resultset;
        };

        push @iterator_for_each_file, $iterator_this_file;
    }

    if (! @iterator_for_each_file) {
        return \&UR::Util::null_sub;  # No matching files
    } elsif (@iterator_for_each_file == 1) {
        return $iterator_for_each_file[0];  # If there's only 1 file, no need to multiplex
    }

    my @next_record;

    my @row_index_sort_order = map { $column_name_to_index_map{$_} } @$sorted_column_names;
    my $row_sorter = sub {
        my($idx_a,$idx_b) = shift;

        for (my $i = 0; $i < @row_index_sort_order; $i++) {
            my $column_num = $row_index_sort_order[$i];

            my $cmp = $next_record[$idx_a]->[$column_num] <=> $next_record[$idx_b]->[$column_num]
                       ||
                      $next_record[$idx_a]->[$column_num] cmp $next_record[$idx_b]->[$column_num];
            return $cmp if $cmp;  # done if they're not equal
        }
    };

    my $iterator = sub {
        return unless @iterator_for_each_file;  # if they're all run out

        my $lowest_slot;
        for(my $i = 0; $i < @iterator_for_each_file; $i++) {
            unless(defined $next_record[$i]) {
                $next_record[$i] = $iterator_for_each_file[$i]->();
                unless (defined $next_record[$i]) {
                    # That iterator is exhausted, splice it out
                    splice(@iterator_for_each_file, $i, 1);
                    splice(@next_record, $i, 1);
                    return unless (@iterator_for_each_file);  # This can happen here if none of the files have matching data
                    redo;
                }
            }

            unless (defined $lowest_slot) {
                $lowest_slot = $i;
                next;
            }

            my $cmp = $row_sorter->($lowest_slot, $i);
            if ($cmp > 0) {
                $lowest_slot = $i;
            }
        }

        my $retval = $next_record[$lowest_slot];
        $next_record[$lowest_slot] = undef;
        return $retval;
    };

    return $iterator;
}

sub initializer_should_create_column_name_for_class_properties {
    1;
}


1;
