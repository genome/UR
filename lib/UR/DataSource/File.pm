package UR::DataSource::File;

# A data source implementation for text files where the fields
# are delimited by commas (or anything else really).  Usually,
# the lines in the file will be sorted by one or more columns,
# but it isn't strictly necessary
#
# For now, it's structured around files where the record is delimited by
# newlines, and the fields are delimited by qr(\s*,\s*).  Those are
# overridable in concrete data sources by specifying record_seperator() and
# delimiter().
# FIXME - work out a way to support record-oriented data as well as line-oriented data


use UR;
use strict;
use warnings;

use Fcntl qw(:DEFAULT :flock);
use Errno qw(EINTR EAGAIN);
use File::Temp;
use File::Basename;

our @CARP_NOT = qw( UR::Context );

class UR::DataSource::File {
    is => ['UR::DataSource'],
    has => [
        delimiter             => { is => 'String', default_value => '\s*,\s*', doc => 'Delimiter between columns on the same line' },
        record_separator      => { is => 'String', default_value => "\n", doc => 'Delimiter between lines in the file' },
        column_order          => { is => 'ARRAY',  doc => 'Names of the columns in the file, in order' },
        cache_size            => { is => 'Integer', default_value => 100 },
        skip_first_line       => { is => 'Integer', default_value => 0, doc => 'Number of lines at the start of the file to skip' },
    ],
    has_optional => [ 
        server                => { is => 'String', doc => 'pathname to the data file' },
        file_list             => { is => 'ARRAY',  doc => 'list of pathnames of equivalent files' },
        sort_order            => { is => 'ARRAY',  doc => 'Names of the columns by which the data file is sorted' },
        constant_values       => { is => 'ARRAY',  doc => 'Property names which are not in the data file(s), but are part of the objects loaded from the data source' },

        quick_disconnect      => { is => 'Boolean', default_value => 1, doc => 'Do not hold the file handle open between requests' },
        handle_class          => { is => 'String', default_value => 'IO::File', doc => 'Class to use for new file handles' },
        
        # REMOVE
        #file_cache_index      => { is => 'Integer', doc => 'index into the file cache where the next read will be placed' },
        _open_query_count      => { is => 'Integer', doc => 'number of queries currently using this data source, used internally' },
        
    ],
    doc => 'A data source for line-oriented files',
};


sub can_savepoint { 0;}  # Doesn't support savepoints
 
sub get_default_handle {
    my $self = shift;

    unless ($self->{'_fh'}) {
        if ($ENV{'UR_DBI_MONITOR_SQL'}) {
            my $time = time();
            UR::DBI->sql_fh->printf("\nFILE OPEN AT %d [%s]\n",$time, scalar(localtime($time)));
        }

        my $filename = $self->server;
        unless (-e $filename) {
            # file doesn't exist
            $filename = '/dev/null';
        }

        my $handle_class = $self->handle_class;
        my $fh = $handle_class->new($filename);
        unless($fh) {
            $self->error_message("Can't open ".$self->server." for reading: $!");
            return;
        }

        $self->_invalidate_cache();

        if ($ENV{'UR_DBI_MONITOR_SQL'}) {
            UR::DBI->sql_fh->printf("FILE: opened %s fileno %d\n\n",$self->server, $fh->fileno);
        }

        $self->{'_fh'} = $fh;
    }
    return $self->{'_fh'};
}

sub disconnect_default_handle {
    my $self = shift;

    if ($self->{'_fh'}) {
        $self->{'_fh'}->close();
    }
}

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

# We're overriding server() so everyone else can have a single way of getting
# the file's pathname instead of having to know about both server and file_list
sub server {
    my $self = shift;

    unless ($self->{'_cached_server'}) {
        if ($self->__server()) {
            $self->{'_cached_server'} = $self->__server();
        } elsif ($self->file_list) {
            my $files = $self->file_list;
            my $count = scalar(@$files);
            my $idx = $$ % $count;
            $self->{'_cached_server'} = $files->[$idx];
        } else {
            die "Data source ",$self->id," didn't specify either server or file_list";
        }
    }
    return $self->{'_cached_server'};
}


# Should be divisible by 3
our $MAX_CACHE_SIZE = 99;
# REMOVE
#sub _file_cache {
#    my $self = shift;
#
#    unless ($self->{'_file_cache'}) {
#        my @cache = ();
#        #$#cache = $self->cache_size;
#        $#cache = $MAX_CACHE_SIZE;
#        $self->{'_file_cache'} = \@cache;
#        $self->file_cache_index(-1);
#
#    }
#    return $self->{'_file_cache'};
#}


# The offset cache is an arrayref containing three pieces of data:
# 0: If this cache slot is being used by a loading iterator
# 1: concatenated data from the sorted columns for comparison with where you are in the file
# 2: the seek position that line came from
sub _offset_cache {
    my $self = shift;

    unless ($self->{'_offset_cache'}) {
        $self->{'_offset_cache'} = [];
    }
    return $self->{'_offset_cache'};
}

sub _allocate_offset_cache_slot {
    my $self = shift;

    my $cache = $self->_offset_cache();
    my $next = scalar(@$cache);
    if ($next > $MAX_CACHE_SIZE) {
        $next = 0;
        # Search for an unused slot
        while ($cache->[$next] and $next <= $MAX_CACHE_SIZE) {
            $next += 3;
        }
        if ($next > $MAX_CACHE_SIZE) {
            Carp::croak("Unable to find an open cache slot because there are too many outstanding loading iterators");
        }
    }
    $cache->[$next] = 1;
    $cache->[$next+1] = undef;
    $cache->[$next+2] = undef;

    return $next;
}


# REMOVE
sub _invalidate_cache {
    my $self = shift;
 
#    my $file_cache = $self->{'_file_cache'};
#    undef($_) foreach @$file_cache;
#    $self->file_cache_index(0);
    return 1;
}

sub _generate_loading_templates_arrayref {
    my($self,$old_sql_cols) = @_;

    my $columns_in_file = $self->column_order;
    my %column_to_position_map;
    for (my $i = 0; $i < @$columns_in_file; $i++) {
        $column_to_position_map{uc $columns_in_file->[$i]} = $i;
    }

    # strip out columns that don't exist in the file
    my $sql_cols;
    foreach my $column_data ( @$old_sql_cols ) {
        my $propertys_column_name = $column_data->[1]->column_name;
        next unless ($propertys_column_name and exists($column_to_position_map{$propertys_column_name}));

        push @$sql_cols, $column_data;
    }

    unless ($sql_cols) {
        $self->error_message("Couldn't determine column information for data source " . $self->id);
        return;
    }

    # reorder the requested columns to be in the same order as the file
    @$sql_cols = sort { $column_to_position_map{$a->[1]->column_name} <=> $column_to_position_map{$b->[1]->column_name}} @$sql_cols;
    my $templates = $self->SUPER::_generate_loading_templates_arrayref($sql_cols);

    if (my $constant_values = $self->constant_values) {
        # Find the first unused index in the loading template
        my $next_template_slot = -1;
        foreach my $tmpl ( @$templates ) {
            foreach my $col ( @{$tmpl->{'column_positions'}} ) {
                if ($col >= $next_template_slot) {
                    $next_template_slot = $col + 1;
                }
            }
        }
        if ($next_template_slot == -1) {
            die "Couldn't determine last column in loading template for data source" . $self->id;
        }
        
        foreach my $prop ( @$constant_values ) {
            push @{$templates->[0]->{'column_positions'}}, $next_template_slot++;
            push @{$templates->[0]->{'property_names'}}, $prop;
        }
    }
 
    return $templates;
}
    

#sub _generate_class_data_for_loading {
#    my($self,$class_meta) = @_;
#
#$DB::single=1;
#    my $parent_class_data = $self->SUPER::_generate_class_data_for_loading($class_meta);
#    
#    my %columns = map { $_ => 1 }  $self->column_order;
#
#    my @all_file_properties;
#    foreach my ( $property_data ) ( @{$parent_class_data->{'all_properties'}} ) {
#        my $property = $property_data->[1];
#        next unless ($columns{$property->column_name});
#
#        push @all_file_properties, $property_data;
#    }
#
#    $parent_class_data->{'all_file_properties'} = \@all_file_properties;
#
#    return $parent_class_data;
#}



#sub _generate_template_data_for_loading {
#    my($self, $rule_template) = @_;
#
#$DB::single=1;
#    my $parent_template_data = $self->SUPER::_generate_template_data_for_loading($rule_template);
#
#    # Classes in this data source don't have a table_name attribute, or column_names in their 
#    # properties.  Rewrite the loading_templates key of $parent_template_data
#   
#
#    return $parent_template_data;
#}


sub _things_in_list_are_numeric {
    my $self = shift;

    foreach ( @{$_[0]} ) {
        no warnings 'numeric';
        return 0 if ($_ + 0 ne $_);
    }
    return 1;
}

# Construct a closure to perform a test on the $index-th column of 
# @$$next_candidate_row.  The closures return 0 is the test is successful,
# -1 if unsuccessful but the file's value was less than $value, and 1
# if unsuccessful and greater.  The iterator that churns throug the file
# knows that if it's comparing an ID/sorted column, and the comparator
# returns 1 then we've gone past the point where we can expect to ever
# find another successful match and we should stop looking
sub _comparator_for_operator_and_property {
    my($self,$property,$next_candidate_row, $index, $operator,$value) = @_;

    if ($operator eq 'between') {
        if ($property->is_numeric and $self->_things_in_list_are_numeric($value)) {
            if ($value->[0] > $value->[1]) {
                # Will never be true
                Carp::carp "'between' comparison will never be true with values ".$value->[0]," and ".$value->[1];
            }
            # numeric 'between' comparison
            return sub {
                       if ($$next_candidate_row->[$index] < $value->[0]) {
                           return -1;
                       } elsif ($$next_candidate_row->[$index] > $value->[1]) {
                           return 1;
                       } else {
                           return 0;
                       }
                   };
        } else {
            if ($value->[0] gt $value->[1]) {
                Carp::carp "'between' comparison will never be true with values ".$value->[0]," and ".$value->[1];
            }
            # A string 'between' comparison
            return sub {
                       if ($$next_candidate_row->[$index] lt $value->[0]) {
                           return -1;
                       } elsif ($$next_candidate_row->[$index] gt $value->[1]) {
                           return 1;
                       } else {
                           return 0;
                       }
                   };
        }

    } elsif ($operator eq '[]' or $operator eq 'in') {
        if ($property->is_numeric and $self->_things_in_list_are_numeric($value)) {
            # Numeric 'in' comparison  returns undef if we're within the range of the list
            # but don't actually match any of the items in the list
            @$value = sort { $a <=> $b } @$value;  # sort the values first
            return sub {
                       if ($$next_candidate_row->[$index] < $value->[0]) {
                           return -1;
                       } elsif ($$next_candidate_row->[$index] > $value->[-1]) {
                           return 1;
                       } else {
                           foreach ( @$value ) {
                               return 0 if $$next_candidate_row->[$index] == $_;
                           }
                           return -1;
                       }
                   };

        } else {
            # A string 'in' comparison
            @$value = sort { $a cmp $b } @$value;
            return sub {
                       if ($$next_candidate_row->[$index] lt $value->[0]) {
                           return -1;
                       } elsif ($$next_candidate_row->[$index] gt $value->[-1]) {
                           return 1;
                       } else {
                           foreach ( @$value ) {
                               return 0 if $$next_candidate_row->[$index] eq $_;
                           }
                           return -1;
                       }
                   };

        }

    } elsif ($operator eq 'not []' or $operator eq 'not in') {
        if ($property->is_numeric and $self->_things_in_list_are_numeric($value)) {
            return sub {
                foreach ( @$value ) {
                    return -1 if $$next_candidate_row->[$index] == $_;
                }
                return 0;
            }

        } else {
            return sub {
                foreach ( @$value ) {
                    return -1 if $$next_candidate_row->[$index] eq $_;
                }
                return 0;
            }
        }

    } elsif ($operator eq 'like') {
        # 'like' is always a string comparison.  In addition, we can't know if we're ahead
        # or behind in the file's ID columns, so the only two return values are 0 and 1
        
        # Convert SQL-type wildcards to Perl-type wildcards
        # Convert a % to a *, and _ to ., unless they're preceeded by \ to escape them.
        # Not that this isn't precisely correct, as \\% should really mean a literal \
        # followed by a wildcard, but we can't be correct in all cases without including 
        # a real parser.  This will catch most cases.
        $value =~ s/(?<!\\)%/.*/g;
        $value =~ s/(?<!\\)_/./g;
        my $regex = qr($value);
        return sub {
                   if ($$next_candidate_row->[$index] =~ $regex) {
                       return 0;
                   } else {
                       return 1;
                   }
               };

    } elsif ($operator eq 'not like') {
        $value =~ s/(?<!\\)%/*/;
        $value =~ s/(?<!\\)_/./;
        my $regex = qr($value);
        return sub {
                   if ($$next_candidate_row->[$index] =~ $regex) {
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
                       return $$next_candidate_row->[$index] <=> $value;
                   };
        } elsif ($operator eq '<') {
            return sub {
                       $$next_candidate_row->[$index] < $value ? 0 : 1;
                   };
        } elsif ($operator eq '<=') {
            return sub {
                       $$next_candidate_row->[$index] <= $value ? 0 : 1;
                   };
        } elsif ($operator eq '>') {
            return sub {
                       $$next_candidate_row->[$index] > $value ? 0 : -1;
                   };
        } elsif ($operator eq '>=') {
            return sub { 
                       $$next_candidate_row->[$index] >= $value ? 0 : -1;
                   };
        } elsif ($operator eq 'true') {
            return sub {
                       $$next_candidate_row->[$index] ? 0 : -1;
                   };
        } elsif ($operator eq 'false') {
            return sub {
                       $$next_candidate_row->[$index] ? 1 : 0;
                   };
        } elsif ($operator eq '!=' or $operator eq 'ne') {
             return sub {
                       $$next_candidate_row->[$index] != $value ? 0 : -1;
             }
        }

    } else {
        # Basic string comparisons
        if ($operator eq '=') {
            return sub {
                       return $$next_candidate_row->[$index] cmp $value;
                   };
        } elsif ($operator eq '<') {
            return sub {
                       $$next_candidate_row->[$index] lt $value ? 0 : 1;
                   };
        } elsif ($operator eq '<=') {
            return sub {
                       $$next_candidate_row->[$index] le $value ? 0 : 1;
                   };
        } elsif ($operator eq '>') {
            return sub {
                       $$next_candidate_row->[$index] gt $value ? 0 : -1;
                   };
        } elsif ($operator eq '>=') {
            return sub {
                       $$next_candidate_row->[$index] ge $value ? 0 : -1;
                   };
        } elsif ($operator eq 'true') {
            return sub {
                       $$next_candidate_row->[$index] ? 0 : -1;
                   };
        } elsif ($operator eq 'false') {
            return sub {
                       $$next_candidate_row->[$index] ? 1 : 0;
                   };
        } elsif ($operator eq '!=' or $operator eq 'ne') {
             return sub {
                       $$next_candidate_row->[$index] ne $value ? 0 : -1;
             }
        }
    }
}
        

our %iterator_data_source; 
our %iterator_cache_slot;

sub create_iterator_closure_for_rule {
    my($self,$rule) = @_;

    my $class_name = $rule->subject_class_name;
    my $class_meta = $class_name->__meta__;
    my $rule_template = $rule->template;

    my $csv_column_order_names = $self->column_order;
    my $csv_column_count = scalar @$csv_column_order_names;
    my %properties_in_rule = map { $_ => 1 }
                             grep { $rule->specifies_value_for($_) }
                             @$csv_column_order_names;

    my $sort_order_names = $self->sort_order;
    my %sort_column_names = map { $_ => 1 } @$sort_order_names;
    my @non_sort_column_names = grep { ! exists($sort_column_names{$_}) } @$csv_column_order_names;

    my %column_name_to_index_map;
    for (my $i = 0; $i < @$csv_column_order_names; $i++) {
        $column_name_to_index_map{$csv_column_order_names->[$i]} = $i;
    }

    # Index in the split-file-data for each sorted column in order
    my @sort_order_column_indexes = map { $column_name_to_index_map{$_} } @$sort_order_names;

    my %property_metas = map { $_ => UR::Object::Property->get(class_name => $class_name, column_name => uc($_)) }
                         @$csv_column_order_names;

    my @rule_columns_in_order;  # The order we should perform rule matches on - value is the index in @next_file_row to test
    my @comparison_for_column;  # closures to call to perform the match - same order as @rule_columns_in_order
    my $last_sort_column_in_rule = -1; # Last index in @rule_columns_in_order that applies when trying "the shortcut"
    my $looking_for_sort_columns = 1;

    my $next_candidate_row;  # This will be filled in by the closure below
    foreach my $column_name ( @$sort_order_names, @non_sort_column_names ) {
        if (! $properties_in_rule{$column_name}) {
            $looking_for_sort_columns = 0;
            next;
        } elsif ($looking_for_sort_columns && $sort_column_names{$column_name}) {
            $last_sort_column_in_rule++;
        } else {
            # There's been a gap in the ID column list in the rule, stop looking for
            # further ID columns
            $looking_for_sort_columns = 0;
        }

        push @rule_columns_in_order, $column_name_to_index_map{$column_name};
         
        my $operator = $rule->operator_for($column_name);
        my $rule_value = $rule->value_for($column_name);
    
        my $comparison_function = $self->_comparator_for_operator_and_property($property_metas{$column_name},
                                                                               \$next_candidate_row,
                                                                               $column_name_to_index_map{$column_name},
                                                                               $operator,
                                                                               $rule_value);
        unless ($comparison_function) {
            Carp::croak("Unknown operator '$operator' in file data source filter");
        }
        push @comparison_for_column, $comparison_function;
    }

    my $split_regex = $self->_regex();

    #my $file_cache = $self->_file_cache();
    #
    ## If there are ID columns mentioned in the rule, and there are items in the
    ## cache, see if any of them are less than the comparators
    #my $matched_in_cache = 0;
    #if ($last_sort_column_in_rule >= 0) {
    #    SEARCH_CACHE:
    #    for(my $file_cache_index = $self->file_cache_index - 1;
    #        $file_cache->[$file_cache_index] and $file_cache_index >= 0;
    #        $file_cache_index--)
    #    {
    #        $next_candidate_row = $file_cache->[$file_cache_index];
    #
    #        MATCH_COMPARATORS:
    #        for (my $i = 0; $i <= $last_sort_column_in_rule; $i++) {
    #            my $comparison = $comparison_for_column[$i]->();
    #            if ($comparison < 0) {
    #                # last row read is earlier than the data we're looking for; we can
    #                # continue on from the next thing in the cache
    #                $matched_in_cache = 1;
    #                $self->{'_last_read_fingerprint'} = $fingerprint; # This will make the iterator skip resetting the position
    #                $self->file_cache_index($file_cache_index + 1);
    #                last SEARCH_CACHE;
   # 
   #             # FIXME - This test only works if we assumme that the ID columns are also UNIQUE columns
   #             } elsif ($comparison > 0 or $i == $last_sort_column_in_rule) {
   #                 # last row read is past what we're looking for ($comparison > 0)
   #                 # or, for the last ID-based comparator, it needs to be strictly less than, otherwise
   #                 # we may have missed some data - back up one slot in the cache and try again
   #                 next SEARCH_CACHE;
   #             }
   #         }
   #     }
   # }

    # FIXME - another performance boost might be to do some kind of binary search
    # against the file to set the initial/next position?
    my $file_pos = 0;

    # search in the offset cache for something helpful
    my $offset_cache = $self->_offset_cache();

    $DB::single=1;
    # If the rule doesn't touch the sorted columns, then we can't use the offset cache for help :(
    if ($last_sort_column_in_rule >= 0) {
        # Starting at index 1 because we're interested in the file and seek data, not if it's in use
        # offset 0 is the in-use flag, offset 1 is a ref to the file data and offset 2 is the file seek pos
        SEARCH_CACHE:
        for (my $i = 1; $i < @$offset_cache; $i+=3) {
            next unless (defined($offset_cache->[$i]) && defined($offset_cache->[$i+1]));

            $next_candidate_row = $offset_cache->[$i];
            for (my $c = 0; $c <= $last_sort_column_in_rule; $c++) {
                my $comparison = $comparison_for_column[$c]->();

                next SEARCH_CACHE if ($comparison > 0);
            }
            # If we made it this far, then the file data in this slot is earlier in the file
            # than the data we're looking for.  So, if the seek pos data is later than what
            # we've found yet, use it instead
            if ($offset_cache->[$i+1] > $file_pos) {
                $file_pos = $offset_cache->[$i+1];
            }
        }
    }

    my($monitor_start_time,$monitor_printed_first_fetch);
    if ($ENV{'UR_DBI_MONITOR_SQL'}) {
        $monitor_start_time = Time::HiRes::time();
        $monitor_printed_first_fetch = 0;
        my @filters_list;
        for (my $i = 0; $i < @rule_columns_in_order; $i++) {
            my $column = $rule_columns_in_order[$i];
            my $column_name = $csv_column_order_names->[$column];
            my $is_sorted = $i <= $last_sort_column_in_rule ? ' (sorted)' : '';
            my $operator = $rule->operator_for($column_name) || '=';
            my $rule_value = $rule->value_for($column_name);   
            if (ref $rule_value eq 'ARRAY') {
                $rule_value = '[' . join(',', @$rule_value) . ']';
            }
            my $filter_string = $column_name . " $operator $rule_value" . $is_sorted;
            push @filters_list, $filter_string;
        }
        my $filter_list = join("\n\t", @filters_list);
        UR::DBI->sql_fh->printf("\nFILE: %s\nFILTERS %s\n\n", $self->server, $filter_list);
    }

    #unless ($matched_in_cache) {
        # this query either doesn't hit the leftmost sorted columns, or nothing
        # has been read from it yet
        #$file_pos = 0;
        $self->{'_last_read_fingerprint'} ||= '';
    #}

    #my $max_cache_size = $self->cache_size;
    my $max_cache_size = $MAX_CACHE_SIZE;
    my $record_separator = $self->record_separator;
    my $cache_slot = $self->_allocate_offset_cache_slot();

    my $fh;  # File handle we'll be reading from
    my $read_fingerprint;   # The stringified version of $iterator (to avoid circular references), filled in below
    my $iterator = sub {

        $DB::single=1;
        unless (ref($fh)) {
            $fh = $self->get_default_handle();
            # Lock the file for reading...  For more fine-grained locking we could move this to
            # after READ_LINE_FROM_FILE: but that would slow down read operations a bit.  If
            # there ends up being a problem with lock contention, go ahead and move it before $line = <$fh>;
            flock($fh,LOCK_SH);
        }

        if ($monitor_start_time && ! $monitor_printed_first_fetch) {
            UR::DBI->sql_fh->printf("FILE: FIRST FETCH TIME: %.4f s\n", Time::HiRes::time() - $monitor_start_time);
            $monitor_printed_first_fetch = 1;
        }

        if ($self->{'_last_read_fingerprint'} ne $read_fingerprint) {
            UR::DBI->sql_fh->printf("FILE: Resetting file position to $file_pos\n") if $ENV{'UR_DBI_MONITOR_SQL'};
            # The last read was from a different request, reset the position and invalidate the cache
            $fh->seek($file_pos,0);
            if ($file_pos == 0) {
                my $skip = $self->skip_first_line;
                while ($skip-- > 0) {
                    scalar(<$fh>);
                }
            }
            $file_pos = $fh->tell();

            $self->_invalidate_cache();
            $self->{'_last_read_fingerprint'} = $read_fingerprint;
        }

        local $/;   # Make sure some wise guy hasn't changed this out from under us
        $/ = $record_separator;

        my $line;
        READ_LINE_FROM_FILE:
        until($line) {
            
            #if ($file_cache->[$file_cache_index]) {
            #    $next_candidate_row = $file_cache->[$file_cache_index++];
            #} else {

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
                $line = <$fh>;

                unless (defined $line) {
                    if ($!) {
                        redo READ_LINE_FROM_FILE if ($! == EAGAIN or $! == EINTR);
                        my $pathname = $self->server();
                        Carp::confess("getline() failed for DataSource $self pathname $pathname boolexpr $rule: $!");
                    }

                    # at EOF.  Close up shop and return
                    flock($fh,LOCK_UN);
                    $fh = undef;
                    $self->_invalidate_cache();
                 
                    if ($monitor_start_time) {
                        UR::DBI->sql_fh->printf("FILE: at EOF\nFILE: TOTAL EXECUTE-FETCH TIME: %.4f s\n", Time::HiRes::time() - $monitor_start_time);
                    }

                    return;
                }

                my $last_read_size = length($line);
                chomp $line;
                # FIXME - to support record-oriented files, we need some replacement for this...
                $next_candidate_row = [ split($split_regex, $line, $csv_column_count) ];
                $#{$a} = $csv_column_count-1;

                #if ($file_cache_index > $max_cache_size) {
                #    # cache is full
                #    # FIXME - this is using the @$file_cache list as a circular buffer with shift/push
                #    # it may be more efficient to keep track of head/tail instead
                #    shift @$file_cache;
                #    push @$file_cache, $next_candidate_row;
                #} else {
                #    $file_cache->[$file_cache_index++] = $next_candidate_row;
                #}
               
            #}

            for (my $i = 0; $i < @rule_columns_in_order; $i++) {
                my $comparison = $comparison_for_column[$i]->();

                if ($comparison > 0 and $i <= $last_sort_column_in_rule) {
                    # We've gone past the last thing that could possibly match
                    #$self->file_cache_index($file_cache_index);

                    if ($monitor_start_time) {
                        UR::DBI->sql_fh->printf("FILE: TOTAL EXECUTE-FETCH TIME: %.4f s\n", Time::HiRes::time() - $monitor_start_time);
                    }

                    flock($fh,LOCK_UN);
                    return;
                
                } elsif ($comparison) {
                    # comparison didn't match, read another line from the file
                    redo READ_LINE_FROM_FILE;
                }

                # That comparison worked... stay in the for() loop for other comparisons
            }
            # All the comparisons return '0', meaning they passed

            $file_pos = $fh->tell();

            # Now see if the offset cache file data is different than the row we just read
            COMPARE_TO_CACHE:
            #for (my $i = 0; $i < @sort_order_column_indexes; $i++) {
            foreach my $column ( @sort_order_column_indexes) {
                no warnings 'uninitialized';
                if ($offset_cache->[$cache_slot+1]->[$column] ne $next_candidate_row->[$column]) {
                    # They're different.  Update the offset cache data
                    $offset_cache->[$cache_slot+1] = $next_candidate_row;
                    $offset_cache->[$cache_slot+2] = $file_pos - $last_read_size;
                    last COMPARE_TO_CACHE;
                }
            }

            return $next_candidate_row;
        }
    }; # end sub $iterator
    $read_fingerprint = $iterator . '';

    Sub::Name::subname('UR::DataSource::File::__datasource_iterator(closure)__', $iterator);

    my $count = $self->_open_query_count() || 0;
    $self->_open_query_count($count+1);
    bless $iterator, 'UR::DataSource::File::Tracker';
    $iterator_data_source{$iterator} = $self;
    $iterator_cache_slot{$iterator} = $cache_slot;
    
    return $iterator;
} 


sub UR::DataSource::File::Tracker::DESTROY {
    my $iterator = shift;
    my $ds = delete $iterator_data_source{$iterator};
    return unless $ds;   # The data source may have gone out of scope first during global destruction

    my $cache_slot = delete $iterator_cache_slot{$iterator};
    if (defined $cache_slot) {
        # Mark this slot unused
        $ds->_offset_cache->[$cache_slot] = 0;
    }

    my $count = $ds->_open_query_count();
    $ds->_open_query_count(--$count);

    return unless ($ds->quick_disconnect);
    if ($count == 0) {
	# All open queries have supposedly been fulfilled.  Close the
	# file handle and undef it so get_default_handle() will re-open if necessary
        my $fh = $ds->{'_fh'};

        UR::DBI->sql_fh->printf("FILE: CLOSING fileno ".fileno($fh)."\n") if ($ENV{'UR_DBI_MONITOR_SQL'});
        flock($fh,LOCK_UN);
	$fh->close();
	$ds->{'_fh'} = undef;
    }
}

# Names of creation params that we should force to be listrefs
our %creation_param_is_list = map { $_ => 1 } qw( column_order file_list sort_order constant_values );
sub create_from_inline_class_data {
    my($class, $class_data, $ds_data) = @_;

    # User didn't specify columns in the file.  Assumme every property is a column, and in the same order
    unless (exists $ds_data->{'column_order'}) {
        $ds_data->{'column_order'} = [];
        foreach my $prop_name ( @{$class_data->{'__properties_in_class_definition_order'}} ) {
            my $prop_data = $class_data->{'has'}->{$prop_name};
            next unless ($prop_data->{'column_name'});  # only interested in concrete properties
             
            push @{$ds_data->{'column_order'}}, $prop_name;
        }
    }

    $ds_data->{'server'} ||= $ds_data->{'path'} || $ds_data->{'file'};

    my %ds_creation_params;
    foreach my $param ( qw( delimieter record_separator column_order cache_size skip_first_line server file_list sort_order constant_values ) ) {
        if (exists $ds_data->{$param}) {
            if ($creation_param_is_list{$param} and ref($ds_data->{$param}) ne 'ARRAY') {
                $ds_creation_params{$param} = \( $ds_data->{$param} );
            } else {
                $ds_creation_params{$param} = $ds_data->{$param};
            }
        }
    }
       
    my($namespace, $class_name) = ($class_data->{'class_name'} =~ m/^(\w+?)::(.*)/);
    my $ds_id = "${namespace}::DataSource::${class_name}";
    my $ds_type = delete $ds_data->{'is'};
    my $ds = $ds_type->create( %ds_creation_params, id => $ds_id );
    return $ds;
}


# The string used to join fields of a row together
#
# Since the 'delimiter' property is interpreted as a regex in the reading
# code, we'll try to be smart about making a real string from that.
#
# subclasses can override this to provide a different implementation
sub join_pattern {
    my $self = shift;

    my $join_pattern = $self->delimiter;

    # make some common substitutions...
    if ($join_pattern eq '\s*,\s*') {
        # The default...
        return ', ';
    }

    $join_pattern =~ s/\\s*//g;  # Turn 0-or-more whitespaces to nothing
    $join_pattern =~ s/\\t/\t/;  # tab
    $join_pattern =~ s/\\s/ /;   # whitespace
    
    return $join_pattern;
}



sub _sync_database {
    my $self = shift;
    my %params = @_;

    unless (ref($self)) {
        if ($self->isa("UR::Singleton")) {
            $self = $self->_singleton_object;
        }
        else {
            die "Called as a class-method on a non-singleton datasource!";
        }
    }

    my $read_fh = $self->get_default_handle();

    my $original_data_file = $self->server;
    my $original_data_dir  = File::Basename::dirname($original_data_file);
    my $use_quick_rename;
    unless (-d $original_data_dir){
        File::Path::mkpath($original_data_dir);
    }
    if (-w $original_data_dir) {
        $use_quick_rename = 1;  # We can write to the data dir
    } elsif (! -w $original_data_file) {
        $self->error_message("Neither the directory nor the file for $original_data_file are writable - cannot sync_database");
        return;
    }


    my $split_regex = $self->_regex();
    my $join_pattern = $self->join_pattern;
    my $record_separator = $self->record_separator;
    local $/;   # Make sure some wise guy hasn't changed this out from under us
    $/ = $record_separator;

    my $csv_column_order_names = $self->column_order;
    $_ = uc foreach @$csv_column_order_names;  # Force all column-namey things to upper-case
    my $csv_column_count = scalar(@$csv_column_order_names);
    my %column_name_to_index_map;
    for (my $i = 0; $i < @$csv_column_order_names; $i++) {
        $column_name_to_index_map{$csv_column_order_names->[$i]} = $i;
    }

    my $changed_objects = delete $params{changed_objects};


    # We're going to assumme all the passed-in objects are of the same class *gulp*
    my $class_name = $changed_objects->[0]->class;
    my $class_meta = UR::Object::Type->get(class_name => $class_name);
    my %column_name_to_property_meta = map { uc($_->column_name) => $_ }
                                       grep { $_->column_name }
                                       $class_meta->all_property_metas;
    my @property_names_in_column_order;
    foreach my $column_name ( @$csv_column_order_names ) {
        my $prop_meta = $column_name_to_property_meta{$column_name};
        unless ($prop_meta) {
            die "Data source " . $self->class . " id " . $self->id . 
                " could not resolve a $class_name property for the data source's column named $column_name";
        }

        push @property_names_in_column_order, $prop_meta->property_name;
    }

    my $insert = [];
    my $update = {};
    my $delete = {};
    foreach my $obj ( @$changed_objects ) {
        if ($obj->isa('UR::Object::Ghost')) {
            # This should be removed from the file
            my $original = $obj->{'db_committed'};
            my $line = join($join_pattern, @{$original}{@property_names_in_column_order}) . $record_separator;
            $delete->{$line} = $obj;

        } elsif ($obj->{'db_committed'}) {
            # This object is changed since it was read in the file
            my $original = $obj->{'db_committed'};
            my $original_line = join($join_pattern, @{$original}{@property_names_in_column_order}) . $record_separator;
            my $changed_line = join($join_pattern, @{$obj}{@property_names_in_column_order}) . $record_separator;
            $update->{$original_line} = $changed_line;
        
        } else {
            # This object is new and should be added to the file
            push @$insert, [ @{$obj}{@property_names_in_column_order} ];
        }
    }

    my $sort_order_names = $self->sort_order;
    foreach my $sort_column_name ( @$sort_order_names ) {
        unless (exists $column_name_to_index_map{uc $sort_column_name}) {
            Carp::croak("Column name '$sort_column_name' appears in the sort_order list, but not in the column_order list for data source ".$self->id);
        }
        $sort_column_name = uc $sort_column_name;  # Force all column-namey things to upper-case
    }
    my $file_is_sorted = scalar(@$sort_order_names);
    my %column_sorts_numerically = map { $_->column_name => $_->is_numeric }
                                   values %column_name_to_property_meta;
    my $row_sort_sub = sub ($$) {
                           my $comparison;

                           foreach my $column_name ( @$sort_order_names ) {
                               my $i = $column_name_to_index_map{$column_name};
                               if ($column_sorts_numerically{$column_name}) {
                                   $comparison = $_[0]->[$i] <=> $_[1]->[$i];
                               } else {
                                   $comparison = $_[0]->[$i] cmp $_[1]->[$i];
                               }
                               return $comparison if $comparison != 0;
                           }
                           return 0;
                       };
    if ($sort_order_names && $file_is_sorted && scalar(@$insert)) {
        # the inserted things should be sorted the same way as the file
        my @sorted = sort $row_sort_sub @$insert;
        $insert = \@sorted;
    }

    my $write_fh;
    my $temp_file_name;
    if ($use_quick_rename) {
        $temp_file_name = sprintf("%s/.%d.%d" , $original_data_dir, time(), $$);
        $write_fh = IO::File->new($temp_file_name, O_WRONLY|O_CREAT);
    } else {
        $write_fh = File::Temp->new(UNLINK => 1);
        $temp_file_name = $write_fh->filename if ($write_fh);
    }
    unless ($write_fh) {
        Carp::croak "Can't create temporary file for writing: $!";
    }

    my $monitor_start_time;
    if ($ENV{'UR_DBI_MONITOR_SQL'}) {
        $monitor_start_time = Time::HiRes::time();
        my $time = time();
        UR::DBI->sql_fh->printf("\nFILE: SYNC_DATABASE AT %d [%s].  Started transaction for %s to temp file %s\n",
                                $time, scalar(localtime($time)), $original_data_file, $write_fh->filename);

    }

    unless (flock($read_fh,LOCK_EX)) {
        Carp::croak($self->class(). ": Can't get exclusive lock for its file: $!");
    }

    # write headers to the new file
    for (my $i = 0; $i < $self->skip_first_line; $i++) {
        my $line = <$read_fh>;
        $write_fh->print($line);
    }

    
    my $line;
    READ_A_LINE:
    while(1) {
        unless ($line) {
            $line = <$read_fh>;
            last unless defined $line;
        }

        if ($file_is_sorted && scalar(@$insert)) {
            # there are sorted things waiting to insert
            my $chomped = $line;
            chomp $chomped;
            my $row = [ split($split_regex, $chomped, $csv_column_count) ];
            my $comparison = $row_sort_sub->($row, $insert->[0]);
            if ($comparison > 0) {
                # write the object's data
                no warnings 'uninitialized';   # Some of the object's data may be undef
                my $new_row = shift @$insert;
                my $new_line = join($join_pattern, @$new_row) . $record_separator;

                if ($ENV{'UR_DBI_MONITOR_SQL'}) {
                    UR::DBI->sql_fh->print("INSERT >>$new_line<<\n");
                }

                $write_fh->print($new_line);
                # Don't undef the last line read, meaning it could still be written to the output...
                next READ_A_LINE;
            }
        }

        if (my $obj = delete $delete->{$line}) {
            if ($ENV{'UR_DBI_MONITOR_SQL'}) {
                UR::DBI->sql_fh->print("DELETE >>$line<<\n");
            }
            $line = undef;
            next;
           
        } elsif (my $changed = delete $update->{$line}) {
            if ($ENV{'UR_DBI_MONITOR_SQL'}) {
                UR::DBI->sql_fh->print("UPDATE replace >>$line<< with >>$changed<<\n");
            }
            $write_fh->print($changed);
            $line = undef;
            next;
            
         } else {
            # This line from the file was unchanged in the app
            $write_fh->print($line);
            $line = undef;
        }
    }

    if (keys %$delete) {
        $self->warning_message("There were ",scalar(keys %$delete)," deleted $class_name objects that did not match data in the file");
    }
    if (keys %$update) {
        $self->warning_message("There were ",scalar(keys %$update)," updated $class_name objects that did not match data in the file");
    }

    # finish out by writing the rest of the new data
    foreach my $new_row ( @$insert ) {
        no warnings 'uninitialized';   # Some of the object's data may be undef
        my $new_line = join($join_pattern, @$new_row) . $record_separator;
        if ($ENV{'UR_DBI_MONITOR_SQL'}) {
            UR::DBI->sql_fh->print("INSERT >>$new_line<<\n");
        }
        $write_fh->print($new_line);
    }
    $write_fh->close();
    
    if ($use_quick_rename) {
        if ($ENV{'UR_DBI_MONITOR_SQL'}) {
            UR::DBI->sql_fh->print("FILE: COMMIT rename $temp_file_name over $original_data_file\n");
        }

        unless(rename($temp_file_name, $original_data_file)) {
            $self->error_message("Can't rename the temp file over the original file: $!");
            return;
        }
    } else {
        # We have to copy the data from the temp file to the original file

        if ($ENV{'UR_DBI_MONITOR_SQL'}) {
            UR::DBI->sql_fh->print("FILE: COMMIT write over $original_data_file in place\n");
        }
        my $new_write_fh = IO::File->new($original_data_file, O_WRONLY|O_TRUNC);
        unless ($new_write_fh) {
            $self->error_message("Can't open $original_data_file for writing: $!");
            return;
        }

        my $temp_file_fh = IO::File->new($temp_file_name);
        unless ($temp_file_fh) {
            $self->error_message("Can't open $temp_file_name for reading: $!");
            return;
        }
 
        while(<$temp_file_fh>) {
            $new_write_fh->print($_);
        }
        
        $new_write_fh->close();
    }

    # Because of the rename/copy process during syncing, the previously opened filehandle may
    # not be valid anymore.  get_default_handle will reopen the file next time it's needed
    $self->{_fh} = undef; 

    if ($ENV{'UR_DBI_MONITOR_SQL'}) {
        UR::DBI->sql_fh->printf("FILE: TOTAL COMMIT TIME: %.4f s\n", Time::HiRes::time() - $monitor_start_time);
    }

    flock($read_fh, LOCK_UN);
    $read_fh->close();

    # FIXME - this is ugly... With RDBMS-type data sources, they will call $dbh->commit() which
    # gets to UR::DBI->commit(), which calls _set_object_saved_committed for them.  Since we're
    # not using DBI we have to do this 2-part thing ourselves.  In the future, we might break
    # out things so the saving to the temp file goes in _sync_database(), and moving the temp
    # file over the original goes in commit()
    unless ($self->_set_specified_objects_saved_uncommitted($changed_objects)) {
        Carp::croak("Error setting objects to a saved state after sync_database.  Exiting.");
        return;
    }
    $self->_set_object_saved_committed($_) foreach @$changed_objects;

    return 1;
}

        

sub initializer_should_create_column_name_for_class_properties {
    1;
}


1;

=pod

=head1 NAME

UR::DataSource::File - Parent class for file-based data sources

=head1 SYNOPSIS
  
  package MyNamespace::DataSource::MyFile;
  class MyNamespace::DataSource::MyFile {
      is => ['UR::DataSource::File', 'UR::Singleton'],
  };
  sub server { '/path/to/file' }
  sub delimiter { "\t" }
  sub column_order { ['thing_id', 'thing_name', 'thing_color' ] }
  sub sort_order { ['thing_id'] }

  package main;
  class MyNamespace::Thing {
      id_by => 'thing_id',
      has => [ 'thing_id', 'thing_name', 'thing_color' ],
      data_source => 'MyNamespace::DataSource::MyFile',
  }
  my @objs = MyNamespace::Thing->get(thing_name => 'Bob');

=head1 DESCRIPTION

Classes which wish to retrieve their data from a regular file can use a UR::DataSource::File-based
data source.  The modules implementing these data sources live under the DataSource subdirectory
of the application's Namespace, by convention.  Besides defining a class for your data source
inheriting from UR::DataSource::File, it should have the following methods, either as properties
or functions in the package.

=head2 Configuration

These methods determine the configuration for your data source.

=over 4

=item server()

server() should return a string representing the pathname of the file where the data is stored.

=item file_list()

The file_list() method should return a listref of pathnames to one or more identical files
where data is stored.   Use file_list() instead of server() when you want to load-balance several NFS
servers, for example.

You must have either server() or file_list() in your module, but not both.  The existence of server()
takes precedence over file_list().

=item delimiter()

delimiter() should return a string representing how the fields in each record are split into
columns.  This string is interpreted as a regex internally.  The default delimiter is "\s*,\s*"
meaning that the file is separated by commas.

=item record_separator()

record_separator() should return a string that gets stored in $/ before getline() is called on the
file's filehandle.  The default record_separator() is "\n" meaning that the file's records are 
separated by newlines.

=item skip_first_line()

skip_first_line() should return a boolean value.  If true, the first line of the file is ignored, for
example if the first line defines the columns in the file.

=item column_order()

column_order() should return a listref of column names in the file.  column_order is required; there
is no default.

=item sort_order()

If the data file is sorted in some way, sort_order() should return a listref of column names (which must
exist in column_order()) by which the file is sorted.  This gives the system a hint about how the file
is structured, and is able to make shortcuts when reading the file to speed up data access.  The default
is to assumme the file is not sorted.

=back

=head1 INHERITANCE

  UR::DataSource

=head1 SEE ALSO

UR, UR::DataSource

=cut
