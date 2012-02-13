package UR::DataSource::Filesystem;

use UR;
use strict;
use warnings;
our $VERSION = "0.37"; # UR $VERSION;

use File::Basename;


# lets you specify the server in several ways:
# server => '/path/name'
#    means there is one file storing the data
# server => [ '/path1/name', '/path2/name' ]
#    means the first tile we need to open the file, pick one (for load balancing)
# server => '/path/to/directory/'
#    means that directory contains one or more files, and the classes using
#    this datasource can have table_name metadata to pick the file
# server => '/path/$param1/$param2.ext'
#    means the values for $param1 and $param2 should come from the input rule.
#    If the rule doesn't specify the param, then it should glob for the possible
#    names at that point in the filesystem
# server => '/path/&method/filename'
#    means the value for that part of the path should come from a method call
#    run as $datasource->$method($rule)

              

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
        sort_order            => { is => 'ARRAY',  doc => 'Names of the columns by which the data file is sorted' },
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

#sub _replace_glob_with_values_in_pathname {
#    my($self, $string, $prop_values_hash) = @_;
#
#    my $glob_pos_offset = $prop_values_hash->{'__glob_pos_offset__'} ||= 0;
#
#    # a * not preceeded by a backslash, delimited by /
#    if ($string =~ m/([^/]*[^/](\*)[^/]*)/) {
#        my $path_part_pos_start = $-[1];
#        my $path_part_pos_end   = $+[1];
#        my $glob_pos = $-[2];
#
#        my $path_segment_including_glob = substr($string, 0, $-[0]);
#        my @glob_matches = glob($path_including_part_with_glob);
#
#        if (exists $prop_values_hash->{$glob_pos}) {
#            # This * was put in previously by a $propname in the spec that wasn't mentioned in the rule
#            # do the filesystem glob and the find out what 
#
#            my @glob_pos = (($path_part_pos_start - $glob_pos_offset) .. ($path_pos_end - $glob_pos_offset));
#            my @these_var_globs = @$prop_values_hash{@glob_pos};
#
#            # Make a regex out of $path_including_part_with_glob, swapping out the * with
#            # a capture so we know the values for this variable obtained from the glob
#            my $regex_as_str = quotemeta($path_including_part_with_glob);
#            $regex_as_str =~ s/\*/\(\.\*\?\)/g;
#            my $regex = qr{$regex_as_str};
#            
#            my @a = map { 
#            
#        } else {
#            # This is a glob put in the original path spec
#            
#            return map { [ 
#            
#            
#    }

1;
