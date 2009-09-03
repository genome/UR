package UR::DataSource::SortedCsvFile;

# A data source implementation for text files where the fields
# are delimited by commas (or anything else really), and the
# lines in the file are already sorted by the ID properties of 
# the class the files are backing up

use UR;
use strict;
use warnings;

class UR::DataSource::SortedCsvFile {
    is => ['UR::DataSource', 'UR::Singleton'],
    is_abstract => 1,
    has => [ 'blahblah'],
#    properties => [
#        server => { is => 'String', doc => 'Pathname to the file holding the data', },
#        delimiter => { is => 'String', default_value => ',', doc => 'The delimiter between fields.  Can be a string containing a regex',},
#        
#        _fh => { is => 'IO::File', calculated_from => ['file'] },
#        _regex => { is => 'Regexp', calculated_from => ['delimiter'] },
#    ],
    doc => 'A read-only data source for files where the lines are already sorted by its ID columns',
};

sub _fh {
    my $self = shift->_singleton_object;

    unless ($self->{'_fh'}) {
        my $fh = IO::File->new($self->server);
        unless($fh) {
            $self->error_message("Can't open ".$self->server." for reading: $!");
            return;
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

sub X_last_read_fingerprint {
    my $self = shift->_singleton_object;

    if (@_) {
        $self->{'_last_read_fingerprint'} = shift;
    } else {
        $self->{'_last_read_fingerprint'};
    }
}

sub _last_file_row_read {
    my $self = shift->_singleton_object;

    if (@_) {
        $self->{'_last_file_row_read'} = shift;
    } else {
        $self->{'_last_file_row_read'};
    }
}


sub _generate_loading_templates_arrayref {
    my($class,$sql_cols) = @_;

    my $templates = $class->SUPER::_generate_loading_templates_arrayref($sql_cols);
$DB::single=1;

    my %class_column_order;

    # column positions need to be adjusted, since SQL-backed data sources can return columns
    # in arbitrary order, but these file-based data sources have the column order pre-determined
    foreach my $template ( @$templates ) {
        my $class_name = $template->{'data_class_name'};

        unless (exists($class_column_order{$class_name})) {
            my @column_order = $class->column_order();
            my $i = 0;
            my %column_order = map { $_ => $i++ } @column_order;

            $class_column_order{$class_name} = \%column_order;
        }

        my $column_order = $class_column_order{$class_name};

        my $i = 0;
        while ($i < @{$template->{'property_names'}}) {
            my $column_name = $template->{'property_names'}->[$i];
            if (exists($column_order->{$column_name})) {
                $template->{'column_positions'}->[$i] = $column_order->{$column_name};
            } else {
                # Not something stored in this file... splice it out.
                splice(@{$template->{'column_positions'}}, $i, 1);
                splice(@{$template->{'property_names'}}, $i, 1);
                next;
            }
            $i++;
        }

        $i = 0;
        while ($i < @{$template->{'id_property_names'}}) {
            my $column_name = $template->{'id_property_names'}->[$i];
            if (exists($column_order->{$column_name})) {
                $template->{'id_column_positions'}->[$i] = $column_order->{$column_name};
            } else {
                # Not something stored in this file... splice it out.
                splice(@{$template->{'id_column_positions'}}, $i, 1);
                splice(@{$template->{'id_property_names'}}, $i, 1);
                next;
            }
            $i++;
        }
    }
    
    return $templates;
}
    


sub _generate_class_data_for_loading {
    my($self,$class_meta) = @_;

$DB::single=1;
    my $parent_class_data = $self->SUPER::_generate_class_data_for_loading($class_meta);


    return $parent_class_data;
}



sub _generate_template_data_for_loading {
    my($self, $rule_template) = @_;

$DB::single=1;
    my $parent_template_data = $self->SUPER::_generate_template_data_for_loading($rule_template);

    # Classes in this data source don't have a table_name attribute, or column_names in their 
    # properties.  Rewrite the loading_templates key of $parent_template_data
   

    return $parent_template_data;
}


sub _things_in_list_are_numeric {
    my $self = shift;

    foreach ( @{$_[0]} ) {
        return 0 if ($_ + 0 ne $_);
    }
    return 1;
}

# Construct a closure to perform a test on the $index-th column of 
# @$next_file_row.  The closures return 0 is the test is successful,
# -1 if unsuccessful but the file's value was less than $value, and 1
# if unsuccessful and greater.  The iterator that churns throug the file
# knows that if it's comparing an ID/sorted column, and the comparator
# returns 1 then we've gone past the point where we can expect to ever
# find another successful match and we should stop looking
sub _comparator_for_operator_and_property {
    my($self,$property,$next_file_row, $index, $operator,$value) = @_;

    if ($operator eq 'between') {
        if ($property->is_numeric and $self->_things_in_list_are_numeric($value)) {
            if ($value->[0] > $value->[1]) {
                # Will never be true
                Carp::carp "'between' comparison will never be true with values ".$value->[0]," and ".$value->[1];
            }
            # numeric 'between' comparison
            return sub {
                       if ($next_file_row->[$index] < $value->[0]) {
                           return -1;
                       } elsif ($next_file_row->[$index] > $value->[1]) {
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
                       if ($next_file_row->[$index] lt $value->[0]) {
                           return -1;
                       } elsif ($next_file_row->[$index] gt $value->[1]) {
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
                       if ($next_file_row->[$index] < $value->[0]) {
                           return -1;
                       } elsif ($next_file_row->[$index] > $value->[-1]) {
                           return 1;
                       } else {
                           foreach ( @$value ) {
                               return 0 if $next_file_row->[$index] == $_;
                           }
                           return -1;
                       }
                   };

        } else {
            # A string 'in' comparison
            @$value = sort { $a cmp $b } @$value;
            return sub {
                       if ($next_file_row->[$index] lt $value->[0]) {
                           return -1;
                       } elsif ($next_file_row->[$index] gt $value->[-1]) {
                           return 1;
                       } else {
                           foreach ( @$value ) {
                               return 0 if $next_file_row->[$index] eq $_;
                           }
                           return -1;
                       }
                   };

        }

    } elsif ($operator eq 'like') {
        # 'like' is always a string comparison.  In addition, we can't know if we're ahead
        # or behind in the file's ID columns, so the only two return values are 0 and undef
        my $regex = qr($value);
        return sub {
                   if ($next_file_row->[$index] =~ $regex) {
                       return 0;
                   } else {
                       return -1;
                   }
               };

    # FIXME - should we only be testing the numericness of the property?
    } elsif ($property->is_numeric and $self->_things_in_list_are_numeric([$value])) {
        # Basic numeric comparisons
        if ($operator eq '=') {
            return sub {
                       return $next_file_row->[$index] <=> $value;
                   };
        } elsif ($operator eq '<') {
            return sub {
                       $next_file_row->[$index] < $value ? 0 : 1;
                   };
        } elsif ($operator eq '<=') {
            return sub {
                       $next_file_row->[$index] <= $value ? 0 : 1;
                   };
        } elsif ($operator eq '>') {
            return sub {
                       $next_file_row->[$index] > $value ? 0 : -1;
                   };
        } elsif ($operator eq '>=') {
            return sub { 
                       $next_file_row->[$index] >= $value ? 0 : -1;
                   };
        }

    } else {
        # Basic string comparisons
        if ($operator eq '=') {
            return sub {
                       return $next_file_row->[$index] cmp $value;
                   };
        } elsif ($operator eq '<') {
            return sub {
                       $next_file_row->[$index] lt $value ? 0 : 1;
                   };
        } elsif ($operator eq '<=') {
            return sub {
                       $next_file_row->[$index] le $value ? 0 : 1;
                   };
        } elsif ($operator eq '>') {
            return sub {
                       $next_file_row->[$index] gt $value ? 0 : -1;
                   };
        } elsif ($operator eq '>=') {
            return sub {
                       $next_file_row->[$index] ge $value ? 0 : -1;
                   };
        }
    }
}
        
    

sub create_iterator_closure_for_rule {
    my($self,$rule) = @_;
$DB::single=1;

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
    my %property_metas = map { $_ => UR::Object::Property->get(class_name => $class_name, property_name => $_) }
                         @csv_column_order;

    my @rule_columns_in_order;  # The order we should perform rule matches on - value is the index in @next_file_row to test
    my @comparison_for_column;  # closures to call to perform the match - same order as @rule_columns_in_order
    my $last_id_column_in_rule = -1; # Last index in @rule_columns_in_order that applies when trying "the shortcut"
    my $looking_for_id_columns = 1;  
 
    my @next_file_row;  # The iterator below will fill this in, and it'll be used by the comparators
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
                                                                               \@next_file_row,
                                                                               $column_name_to_index_map{$column_name},
                                                                               $operator,
                                                                               $rule_value);
        push @comparison_for_column, $comparison_function;
    }

    my $fh = $self->_fh();
    my $split_regex = $self->_regex();

    # A method to tell if there's been interleaved reads on the same file handle.  If the
    # last read was done at a different place in the file, then we need to reset the
    # file pointer.  We're using the address of @next_file_row, and that will probably be unique
    # enough during the life of a request to work out ok
    my $fingerprint = \@next_file_row;

    # FIXME - another performance boost might be to do some kind of binary search
    # against the file to set the initial/next position?
    my $file_pos;

    my $last_file_row_read = $self->_last_file_row_read();
    if ($last_id_column_in_rule > 0 and $last_file_row_read) {
        @next_file_row = @$last_file_row_read;
        for (my $i = 0; $i <= $last_id_column_in_rule; $i++) {
            my $comparison = $comparison_for_column[$i]->();
            if ($comparison < 0) {
                # last row read is earlier than the data we're looking for; we can
                # continue on from whatever the current position is
                $self->_last_file_row_read(\@next_file_row); # This will make the iterator skip resetting the position
                last;

            } elsif ($comparison > 0 or $i == $last_id_column_in_rule) {
                # last row read is past what we're looking for ($comparison > 0)
                # or, for the last ID-based comparator, it needs to be strictly less than, otherwise
                # we may have missed some data
                $file_pos = 0;
                $self->_last_file_row_read('');  # This will force a seek at the start of the iterator
           
            }
        }

    } else {
        # this query either doesn't hit the leftmost sorted columns, or nothing
        # has been read from it yet
        $file_pos = 0;
        $self->_last_file_row_read('');  # This will force a seek at the start of the iterator
    }

    my $iterator = sub {

        if ($self->_last_file_row_read() ne $fingerprint) {
            $fh->seek($file_pos,0);
        }

        my $line;
        READ_LINE_FROM_FILE:
        until($line) {
            my $line = $fh->getline();
            unless ($line) {
                @next_file_row = ();
                $fh = undef;
                return;
            }

            @next_file_row = split($split_regex, $line);

            for (my $i = 0; $i < @rule_columns_in_order; $i++) {
                my $comparison = $comparison_for_column[$i]->();

                if ($comparison > 0 and $i <= $last_id_column_in_rule) {
                    # We've gone past the last thing that could possibly match
                    return;
                
                } elsif ($comparison != 0) {
                    redo READ_LINE_FROM_FILE;

                }

                # That comparison worked... keep in the for() loop for other comparisons
            }
            # All the comparisons return '0', meaning they passed
            $self->_last_file_row_read(\@next_file_row);
            $file_pos = $fh->tell();
            return \@next_file_row;
        }
    }; # end sub $iterator
           
    return $iterator;
} 


sub column_order {
    my $class = shift;
    $class = ref($class) || $class;

    Carp::carp "$class didn't specify column_order()";
}

sub sort_order {
    my $class = shift;
    $class = ref($class) || $class;

    Carp::carp "$class didn't specify sort_order()";
}




1;
