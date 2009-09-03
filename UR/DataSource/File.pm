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

use Sub::Name ();
use Sub::Install ();


# FIXME child classes are required to define methods to return server (name of the file),
# delimiter, column_order and sort_order.  These should be properties of the data source
# and not methods in the namespace...

class UR::DataSource::File {
    is => ['UR::DataSource', 'UR::Singleton'],
    is_abstract => 1,
    has => [ 
        last_read_fingerprint => { is => 'String', doc => 'Keeps track of the last request triggering a read' },
        file_cache_index      => { is => 'Integer', doc => 'index into the file cache where the next read will ibe placed' },
        cache_size            => { is => 'Integer', default_value => 100 },
        
    ],
    doc => 'A read-only data source for line-oriented files',
};


my $sql_fh;

sub get_default_handle {
    my $self = shift->_singleton_object;

    unless ($self->{'_fh'}) {
        if ($ENV{'UR_DBI_MONITOR_SQL'}) {
            $sql_fh = UR::DBI->sql_fh();
            my $time = time();
            $sql_fh->printf("\nCSV OPEN AT %d [%s]\n\n",$time, scalar(localtime($time)));
        }

        my $filename = $self->server;
        unless (-e $filename) {
            # file doesn't exist
            my $fh = IO::File->new($filename, '>');
            unless ($fh) {
                $self->error_message("$filename does not exist, and can't be created: $!");
                return;
            }
            $fh->close();
        }

        my $fh = IO::File->new($filename);
        unless($fh) {
            $self->error_message("Can't open ".$self->server." for reading: $!");
            return;
        }

        $self->_invalidate_cache();

        if ($ENV{'UR_DBI_MONITOR_SQL'}) {
            $sql_fh->printf("\nCSV: opened %s fileno %d\n\n",$self->server, $fh->fileno);
        }

        $self->{'_fh'} = $fh;
    }
    return $self->{'_fh'};
}

sub _regex {
    my $self = shift->_singleton_object;

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

# Subclasses can override this to return a string containing the pathname of the file
# to open.  Alternatively, the subclass can implement a method called file_list that returns 
# a list of file paths, all of which should contain the same data - as a way to, say, load
# balance NFS servers
sub server {
    my $self = shift->_singleton_object;

    unless ($self->{'_cached_server'}) {
        unless ($self->can('file_list')) {
            my $class = ref($self);
            die "Class $class didn't implement server() to specify file path";
        }

        my @files = $self->file_list;
        my $count = scalar(@files);
        my $idx = $$ % $count;
        $self->{'_cached_server'} = $files[$idx];
    }
    return $self->{'_cached_server'};
}


# Override if your file is delimited by something else
sub delimiter {
    '\s*,\s*';
}

sub record_separator {
    "\n";
}


# FIXME Looks like the AccessorWriter doesn't properly make accessors for singleton classes?!
sub last_read_fingerprint {
    my $self = shift->_singleton_object;

    if (@_) {
        $self->{'_last_read_fingerprint'} = shift;
    }
    $self->{'_last_read_fingerprint'};
}

sub file_cache_index {
    my $self = shift->_singleton_object;

    if (@_) {
        $self->{'_file_cache_index'} = shift;
    }
    $self->{'_file_cache_index'};
}

sub open_query_count {
    my $self = shift->_singleton_object;

    if (@_) {
        $self->{'_open_query_count'} = shift;
    }
    $self->{'_open_query_count'} || 0;
}


# Derived classes can set this to 1 if the first line of the file
# is a header and should be skipped
sub skip_first_line {
    0;
}

our $MAX_CACHE_SIZE = 100;
sub _file_cache {
    my $self = shift->_singleton_object;

    unless ($self->{'_file_cache'}) {
        my @cache = ();
        #$#cache = $self->cache_size;
        $#cache = $MAX_CACHE_SIZE;
        $self->{'_file_cache'} = \@cache;
        $self->file_cache_index(-1);

    }
    return $self->{'_file_cache'};
}

sub _invalidate_cache {
    my $self = shift->_singleton_object;
 
    my $file_cache = $self->{'_file_cache'};
    undef($_) foreach @$file_cache;
    $self->file_cache_index(0);
}

sub _generate_loading_templates_arrayref {
    my($class,$old_sql_cols) = @_;

    my @columns_in_file = $class->column_order;
    my %column_to_position_map;
    for (my $i = 0; $i < @columns_in_file; $i++) {
        $column_to_position_map{uc $columns_in_file[$i]} = $i;
    }

    # strip out columns that don't exist in the file
    my $sql_cols;
    foreach my $column_data ( @$old_sql_cols ) {
        my $propertys_column_name = $column_data->[1]->column_name;
        next unless (exists $column_to_position_map{$propertys_column_name});

        push @$sql_cols, $column_data;
    }

    unless ($sql_cols) {
        $class->error_message("Couldn't determine column information for data source $class");
        return;
    }

    # reorder the requested columns to be in the same order as the file
    @$sql_cols = sort { $column_to_position_map{$a->[1]->column_name} <=> $column_to_position_map{$b->[1]->column_name}} @$sql_cols;
    my $templates = $class->SUPER::_generate_loading_templates_arrayref($sql_cols);
 
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

    } elsif ($operator eq '[]') {
        if ($property->is_numeric and $self->_things_in_list_are_numeric($value)) {
            # Numeric 'in' comparison  returns undef is we're within the range of the list
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

    } elsif ($operator eq 'like') {
        # 'like' is always a string comparison.  In addition, we can't know if we're ahead
        # or behind in the file's ID columns, so the only two return values are 0 and 1
        my $regex = qr($value);
        return sub {
                   if ($$next_candidate_row->[$index] =~ $regex) {
                       return 0;
                   } else {
                       return 1;
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
        }
    }
}
        

our $READ_FINGERPRINT = 0;
our %iterator_data_source; 

sub create_iterator_closure_for_rule {
    my($self,$rule) = @_;

    my $class_name = $rule->subject_class_name;
    my $class_meta = $class_name->get_class_object;
    my $rule_template = $rule->rule_template;

    my @csv_column_order = $self->column_order;
    my %properties_in_rule = map { $_ => 1 }
                             grep { $rule->specifies_value_for_property_name($_) }
                             @csv_column_order;

    my %sort_columns = map { $_ => 1 } $self->sort_order;
    my @non_sort_columns = grep { ! exists($sort_columns{$_}) } @csv_column_order;

    my %column_name_to_index_map;
    for (my $i = 0; $i < @csv_column_order; $i++) {
        $column_name_to_index_map{$csv_column_order[$i]} = $i;
    }

    # FIXME - properties for these classes don't have the column_name field specified 
    # we'll work around it for now by using the property_name, but column_name is really the right 
    # thing to use
    my %property_metas = map { $_ => UR::Object::Property->get(class_name => $class_name, column_name => uc($_)) }
                         @csv_column_order;

    my @rule_columns_in_order;  # The order we should perform rule matches on - value is the index in @next_file_row to test
    my @comparison_for_column;  # closures to call to perform the match - same order as @rule_columns_in_order
    my $last_id_column_in_rule = -1; # Last index in @rule_columns_in_order that applies when trying "the shortcut"
    my $looking_for_id_columns = 1;  
 
    my $next_candidate_row;  # This will be filled in by the closure below
    foreach my $column_name ( $self->sort_order, @non_sort_columns ) {
        if (! $properties_in_rule{$column_name}) {
            $looking_for_id_columns = 0;
            next;
        } elsif ($looking_for_id_columns && $sort_columns{$column_name}) {
            $last_id_column_in_rule++;
        } else {
            # There's been a gap in the ID column list in the rule, stop looking for
            # further ID columns
            $looking_for_id_columns = 0;
        }

        push @rule_columns_in_order, $column_name_to_index_map{$column_name};
         
        my $operator = $rule->specified_operator_for_property_name($column_name);
        my $rule_value = $rule->specified_value_for_property_name($column_name);
    
        my $comparison_function = $self->_comparator_for_operator_and_property($property_metas{$column_name},
                                                                               \$next_candidate_row,
                                                                               $column_name_to_index_map{$column_name},
                                                                               $operator,
                                                                               $rule_value);
        push @comparison_for_column, $comparison_function;
    }

    my $fh = $self->get_default_handle();
    my $split_regex = $self->_regex();

    # A method to tell if there's been interleaved reads on the same file handle.  If the
    # last read was done at a different place in the file, then we need to reset the
    # file pointer.  This will be a monotonically increasing number that's unique to each
    # request
    my $fingerprint = $READ_FINGERPRINT++;  

    # FIXME - another performance boost might be to do some kind of binary search
    # against the file to set the initial/next position?
    my $file_pos;

    my $file_cache = $self->_file_cache();

    # If there are ID columns mentioned in the rule, and there are items in the
    # cache, see if any of them are less than the comparators
    my $matched_in_cache = 0;
    if ($last_id_column_in_rule >= 0) {
        SEARCH_CACHE:
        for(my $file_cache_index = $self->file_cache_index - 1;
            $file_cache->[$file_cache_index] and $file_cache_index >= 0;
            $file_cache_index--)
        {
            $next_candidate_row = $file_cache->[$file_cache_index];

            MATCH_COMPARATORS:
            for (my $i = 0; $i <= $last_id_column_in_rule; $i++) {
                my $comparison = $comparison_for_column[$i]->();
                if ($comparison < 0) {
                    # last row read is earlier than the data we're looking for; we can
                    # continue on from the next thing in the cache
                    $matched_in_cache = 1;
                    $self->last_read_fingerprint($fingerprint); # This will make the iterator skip resetting the position
                    $self->file_cache_index($file_cache_index + 1);
                    last SEARCH_CACHE;
    
                # FIXME - This test only works if we assumme that the ID columns are also UNIQUE columns
                } elsif ($comparison > 0 or $i == $last_id_column_in_rule) {
                    # last row read is past what we're looking for ($comparison > 0)
                    # or, for the last ID-based comparator, it needs to be strictly less than, otherwise
                    # we may have missed some data - back up one slot in the cache and try again
                    next SEARCH_CACHE;
                }
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
            my $column_name = $csv_column_order[$column];
            my $is_sorted = $i <= $last_id_column_in_rule ? ' (sorted)' : '';
            my $operator = $rule->specified_operator_for_property_name($column_name) || '=';
            my $rule_value = $rule->specified_value_for_property_name($column_name);   
            if (ref $rule_value eq 'ARRAY') {
                $rule_value = '[' . join(',', @$rule_value) . ']';
            }
            my $filter_string = $column_name . " $operator $rule_value" . $is_sorted;
            push @filters_list, $filter_string;
        }
        my $filter_list = join("\n\t", @filters_list);
        $sql_fh->printf("\nCSV: %s\nFILTERS %s\n\n", $self->server, $filter_list);
    }

    unless ($matched_in_cache) {
        # this query either doesn't hit the leftmost sorted columns, or nothing
        # has been read from it yet
        $file_pos = 0;
        $self->last_read_fingerprint('');  # This will force a seek and cache invalidation at the start of the iterator
    }

    #my $max_cache_size = $self->cache_size;
    my $max_cache_size = $MAX_CACHE_SIZE;
    my $record_separator = $self->record_separator;

    my $iterator = sub {

        if ($monitor_start_time && ! $monitor_printed_first_fetch) {
            $sql_fh->printf("CSV: FIRST FETCH TIME: %.4f s\n", Time::HiRes::time() - $monitor_start_time);
            $monitor_printed_first_fetch = 1;
        }

        if ($self->last_read_fingerprint() ne $fingerprint) {
            $sql_fh->printf("CSV: Rewinding file position to the start\n") if $ENV{'UR_DBI_MONITOR_SQL'};
            # The last read was from a different request, reset the position and invalidate the cache
            $fh->seek($file_pos,0);
            local $/;   # Make sure some wise guy hasn't changed this out from under us
            $/ = $record_separator;
            $fh->getline() if ($self->skip_first_line());

            $self->_invalidate_cache();
        }

        my $file_cache_index = $self->file_cache_index();

        my $line;
        READ_LINE_FROM_FILE:
        until($line) {
            
            if ($file_cache->[$file_cache_index]) {
                $next_candidate_row = $file_cache->[$file_cache_index++];
            } else {
                $self->last_read_fingerprint($fingerprint);

                local $/;   # Make sure some wise guy hasn't changed this out from under us
                $/ = $record_separator;
                my $line = $fh->getline();

                unless (defined $line) {
                    # at EOF.  Close up shop and return
                    $fh = undef;
                    $self->_invalidate_cache();
                 
                    return;
                }

                chomp $line;
                # FIXME - to support record-oriented files, we need some replacement for this...
                $next_candidate_row = [ split($split_regex, $line) ];

                if ($file_cache_index > $max_cache_size) {
                    # cache is full
                    # FIXME - this is using the @$file_cache list as a circular buffer with shift/push
                    # it may be more efficient to keep track of head/tail instead
                    shift @$file_cache;
                    push @$file_cache, $next_candidate_row;
                } else {
                    $file_cache->[$file_cache_index++] = $next_candidate_row;
                }
               
            }

            for (my $i = 0; $i < @rule_columns_in_order; $i++) {
                my $comparison = $comparison_for_column[$i]->();

                if ($comparison > 0 and $i <= $last_id_column_in_rule) {
                    # We've gone past the last thing that could possibly match
                    $self->file_cache_index($file_cache_index);

                    if ($monitor_start_time) {
                        $sql_fh->printf("CSV: TOTAL EXECUTE-FETCH TIME: %.4f s\n", Time::HiRes::time() - $monitor_start_time);
                    }


                    return;
                
                } elsif ($comparison != 0) {
                    redo READ_LINE_FROM_FILE;

                }

                # That comparison worked... stay in the for() loop for other comparisons
            }
            # All the comparisons return '0', meaning they passed
            $file_pos = $fh->tell();
            $self->file_cache_index($file_cache_index);
            return $next_candidate_row;
        }
    }; # end sub $iterator

    my $count = $self->open_query_count();
    $self->open_query_count($count+1);
    bless $iterator, 'UR::DataSource::File::Tracker';
    $iterator_data_source{$iterator} = $self;
    
    return $iterator;
} 


sub UR::DataSource::File::Tracker::DESTROY {
    my $iterator = shift;
    my $ds = delete $iterator_data_source{$iterator};
    my $count = $ds->open_query_count();
    $ds->open_query_count(--$count);
    if ($count == 0) {
	# All open queries have supposedly been fulfilled.  Close the
	# file handle and undef it so get_default_handle() will re-open if necessary
	my $self_obj = $ds->_singleton_object;
        my $fh = $self_obj->{'_fh'};

        $sql_fh->printf("CSV: CLOSING fileno ".fileno($fh)."\n") if ($ENV{'UR_DBI_MONITOR_SQL'});
	$fh->close();
	$self_obj->{'_fh'} = undef;
    }
}


sub column_order {
    my $class = shift;
    $class = ref($class) || $class;

    Carp::carp "$class didn't specify column_order()";
}

sub sort_order {
    return ();   # default is to assumme its not sorted
    #my $class = shift;
    #$class = ref($class) || $class;
    #
    #Carp::carp "$class didn't specify sort_order()";
}


sub create_from_inline_class_data {
    my($self, $class_data, $ds_data) = @_;

    my($namespace,$class_name) = ($class_data->{'class_name'} =~ m/^(\w+)::(.*)/);
    my $ds_name = "${namespace}::DataSource::${class_name}";

    if ($ds_data->{'is_sorted'} and $ds_data->{'sort_order'}) {
        die $class_data->{'class_name'}.": cannot specify both 'is_sorted' and 'sort_order' in the class definition's inline data_source";
    }
    if (exists($ds_data->{'sort_order'}) and ref($ds_data->{'sort_order'}) ne 'ARRAY') {
        die $class_data->{'class_name'}.": 'sort_order' must be an arrayref in the class definition's inline data_+source";
    }
    delete $ds_data->{'is_sorted'};


    $ds_data->{'server'} ||= $ds_data->{'path'} || $ds_data->{'file'};
    delete $ds_data->{'path'};
    delete $ds_data->{'file'};

    
    if (exists($ds_data->{'column_order'})) {
        unless (ref($ds_data->{'column_order'}) eq 'ARRAY') {
            $self->error_message($class_data->{'class_name'}.": column_order must bt an arrayerf");
            return;
        }
    } else {
        $ds_data->{'column_order'} = [];
        foreach my $prop_name ( @{$class_data->{'__properties_in_class_definition_order'}} ) {
            my $prop_data = $class_data->{'has'}->{$prop_name};
            next unless ($prop_data->{'column_name'});  # only interested in concrete properties
             
            push @{$ds_data->{'column_order'}}, $prop_name;
        }
    }

    $ds_data->{'file_list'} ||= $ds_data->{'files'};
    if (defined $ds_data->{'file_list'}) {
       unless(ref($ds_data->{'file_list'}) eq 'ARRAY') {
           $self->error_message($class_data->{'class_name'}.": 'file_list' must be an arrayref");
           return;
       }
    }
    delete $ds_data->{'files'};

    if ($ds_data->{'is_sorted'} and ! @{$ds_data->{'sort_order'}}) {
        @{$ds_data->{'sort_order'}} = @{$ds_data->{'column_order'}};
    }
    
    my %subs_to_create;
    delete $ds_data->{'is'};
    foreach my $key ( qw( server delimiter column_order sort_order skip_first_line file_list ) ) {
        my $val = delete $ds_data->{$key};
        next unless defined $val;
        $subs_to_create{$key} = $val;
    }
    if (keys %$ds_data) {
        die $class_data->{'class_name'}. ": Unrecognized parameters for inline data_source: (".join(',',keys %$ds_data).")";
    }

    # These methods need to return a list, but the user specifies them as a listref
    foreach my $method_returns_list ( qw( sort_order column_order file_list ) ) {
        if (my $list = delete $subs_to_create{$method_returns_list}) {
           my @value = @$list;
           my $sub = sub { @value };
           Sub::Name::subname "${ds_name}::${method_returns_list}" => $sub;
           Sub::Install::reinstall_sub({
                into => $ds_name,
                as   => $method_returns_list,
                code => $sub,
            });
        }
    }

    # The rest of them return scalars
    foreach my $key ( keys %subs_to_create ) {
        my $value = $subs_to_create{$key};
        my $sub = sub { $value };
        Sub::Name::subname "${ds_name}::${key}" => $sub;
        Sub::Install::reinstall_sub({
                into => $ds_name,
                as   => $key,
                code => $sub,
        });
    }

    my $c=UR::Object::Type->define(
        class_name => $ds_name,
        is => __PACKAGE__,
    );
        
    return $ds_name;
}



1;

=pod

=head1 NAME

UR::DataSource::File - Parent class for file-based data sources

=head1 SYNOPSIS
  
  package MyNamespace::DataSource::MyFile;
  class MyNamespace::DataSource::MyFile {
      is => ['UR::DataSource::File'],
  };
  sub server { '/path/to/file' }
  sub delimiter { "\t" }
  sub column_order { qw( thing_id thing_name thing_color ) }
  sub sort_order { qw( thing_id ) }

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
inheriting from UR::DataSource::File, the module should override the following methods:

=head2 Configuration

These methods determine the configuration for your data source.  They should require no arguments.

=over 4

=item server()

The server() method should return a string representing the pathname of the file where the data is stored.

=item file_list()

The file_list() method should return a list (not a listref) of pathnames to one or more identical files
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

column_order() should return a list of column names in the file (not a listref).  Your module must
define column_order(); there is no default.

=item sort_order()

If the data file is sorted, you should define sort_order() to return a list of column names (which must
exist in column_order) by which the file is sorted.  This gives the system a hint about how the file
is structured, and is able to make shortcuts when reading the file to speed up data access.  The default
is to assumme the file is not sorted.

=back

=head1 INHERITANCE

  UR::DataSource

=head1 SEE ALSO

UR, UR::DataSource

=head1 AUTHOR

Anthony Brummett <abrummet@watson.wustl.edu>

=cut
