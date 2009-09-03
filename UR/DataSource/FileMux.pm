package UR::DataSource::FileMux;

use UR;
use strict;
use warnings;

class UR::DataSource::FileMux {
    is => ['UR::DataSource'],
    doc => 'A factory for other datasource factories that is able to pivot depending on parameters in the rule used for get()',
    has => [
        delimiter             => { is => 'String', default_value => '\s*,\s*', doc => 'Delimiter between columns on the same line' },
        record_separator      => { is => 'String', default_value => "\n", doc => 'Delimiter between lines in the file' },
        column_order          => { is => 'ARRAY',  doc => 'Names of the columns in the file, in order' },
        cache_size            => { is => 'Integer', default_value => 100 },
        skip_first_line       => { is => 'Integer', default_value => 0 },
        file_resolver         => { is => 'CODE',   doc => 'subref that will return a pathname given a rule' },
        constant_values       => { is => 'ARRAY',  default_value => [], doc => 'Property names which are not in the data file(s), but are part of the objects loaded from the data source' },
    ],
    has_optional => [
        server                => { is => 'String', doc => 'pathname to the data file' },
        file_list             => { is => 'ARRAY',  doc => 'list of pathnames of equivalent files' },
        sort_order            => { is => 'ARRAY',  doc => 'Names of the columns by which the data file is sorted' },
        required_for_get      => { is => 'ARRAY',  doc => 'Property names which must appear in any get() request using this data source.  It is used to build the argument list for the file_resolver sub' },
    ],
};


# The concreate data sources will be of this type
sub _delegate_data_source_class {
    'UR::DataSource::File';
}


my %WORKING_RULES; # Avoid recusion when infering values from rules
sub create_iterator_closure_for_rule {
    my($self,$rule) = @_;

$DB::single=1;
    if ($WORKING_RULES{$rule->id}++) {
        my $subject_class = $rule->subject_class_name;
        $self->error_message("Recursive entry into create_iterator_closure_for_rule() for class $subject_class rule_id ".$rule->id);
        $WORKING_RULES{$rule->id}--;
        return;
    }

    my $context = UR::Context->get_current;
    my $required_for_get = $self->required_for_get;
    my @all_resolver_params;
    for(my $i = 0; $i < @$required_for_get; $i++) {
        my $param_name = $required_for_get->[$i];
        my @values = $context->infer_property_value_from_rule($param_name, $rule);
        unless (@values) {
            # Hack: the above infer...rule()  returned 0 objects, so $all_params_loaded made
            # a note of it.  Later on, if the user supplies more params such that it would be
            # able to resolve a file, we'll never get here, because the Context will see that a
            # superset of the params (this current invocation without sufficient params) was already
            # tried and results should be entirely in the cache - ie. no objects.
            # So... remove the evidence that we tried this in case the user is catching the die
            # below and will continue on
            $context->_forget_loading_was_done_with_class_and_rule($rule->subject_class_name, $rule);
            die "Can't resolve data source: no $param_name specified in rule with id ".$rule->id;
        }

        if (@values == 1 and ref($values[0]) eq 'ARRAY') {
            @values = @{$values[0]};
        }

        unless ($rule->specifies_value_for_property_name($param_name)) {
            if (scalar(@values) == 1) {
                $rule = $rule->add_filter($param_name => $values[0]);
            } else {
                $rule = $rule->add_filter($param_name => \@values);
            }
        }
        $all_resolver_params[$i] = \@values;
    }
    my @resolver_param_combinations = &_get_combinations_of_resolver_params(@all_resolver_params);

    # Each combination of params ends up being from a different data source.  Make an
    # iterator pulling from each of them
    my @data_source_iterators;
    my $file_resolver = $self->{'file_resolver'};
    if (ref($file_resolver) ne 'CODE') {
        # Hack!  The data source is probably a singleton class and there's a file_resolver method
        # defined
        $file_resolver = $self->can('file_resolver');
    } 

    my $concrete_ds_type = $self->_delegate_data_source_class;
    my %sub_ds_params = $self->_common_params_for_concrete_data_sources();

    foreach my $resolver_params ( @resolver_param_combinations ) {

        my @sub_ds_name_parts;
        my $this_ds_rule_params = $rule->legacy_params_hash;
        for (my $i = 0; $i < @$required_for_get; $i++) {
            push @sub_ds_name_parts, $required_for_get->[$i] . $resolver_params->[$i];
            $this_ds_rule_params->{$required_for_get->[$i]} = $resolver_params->[$i];
        }

        my $sub_ds_id = join('::', $self->id, @sub_ds_name_parts);
        my $sub_ds;
        unless ($sub_ds = $concrete_ds_type->get($sub_ds_id)) {

            my $file_path = $file_resolver->(@$resolver_params);
            unless (defined $file_path) {
                die "Can't resolve data source: resolver for " .
                    $rule->subject_class_name .
                    " returned undef for params " . join(',',@$resolver_params);
            }

            $sub_ds = $concrete_ds_type->create(
                          id => $sub_ds_id,
                          %sub_ds_params,
                          server => $file_path,
                      );
        }
        unless ($sub_ds) {
            die "Can't get data source with ID $sub_ds_id";
        }

        my $this_ds_rule = UR::BoolExpr->resolve_for_class_and_params($rule->subject_class_name,%$this_ds_rule_params);

        my @constant_value_properties = @{$self->constant_values};
        my @constant_values = map { $this_ds_rule->specified_value_for_property_name($_) }
                              @constant_value_properties;
        push @data_source_iterators, { ds_iterator => $sub_ds->create_iterator_closure_for_rule($this_ds_rule),
                                       constant_values => \@constant_values,
                                     };
 
        
    }
    delete $WORKING_RULES{$rule->id};

    # Results are coming from more than one data source.  Make an iterator encompassing all of them
    my $iterator = sub {
        while (@data_source_iterators) {
            my $ds_iterator = $data_source_iterators[0]->{'ds_iterator'};
            my @constant_values = @{$data_source_iterators[0]->{'constant_values'}};

            while (my $thing = $ds_iterator->()) {
                push @$thing, @constant_values;
                return $thing;
            }
            shift @data_source_iterators;
        }

        return;
    };
    return $iterator;
}


sub _generate_loading_templates_arrayref {
    my $self = shift;
    my $delegate_class = $self->_delegate_data_source_class();

    my $function_name = $delegate_class . '::_generate_loading_templates_arrayref';
    no strict 'refs';
    return &$function_name($self,@_);
}


# Not a method!  Called from the create_iterator_closure_from_rule closures
sub _get_combinations_of_resolver_params {
    my(@resolver_params) = @_;

    return [] unless @resolver_params;

    my @sub_combinations = &_get_combinations_of_resolver_params(@resolver_params[1..$#resolver_params]);

    my @retval;
    foreach my $item ( @{$resolver_params[0]} ) {
        foreach my $sub_combinations ( @sub_combinations ) {
            push @retval, [ $item, @$sub_combinations ];
        }
    }

    return @retval;
}


sub _normalize_file_resolver_details {
    my($class, $class_data, $ds_data) = @_;

    my $path_resolver_coderef;
    my @required_for_get;
    my $class_name = $class_data->{'class_name'};

    if (exists $ds_data->{'required_for_get'}) {
        @required_for_get = @{$ds_data->{'required_for_get'}};
        my $user_supplied_resolver = $ds_data->{'file_resolver'} || $ds_data->{'resolve_file_with'} ||
                                     $ds_data->{'resolve_path_with'};
        if (ref($user_supplied_resolver) eq 'CODE') {
            $path_resolver_coderef = $user_supplied_resolver;
        } elsif (! ref($user_supplied_resolver)) {
            # It's a functcion name
            $path_resolver_coderef = $class_name->can($user_supplied_resolver);
            unless ($path_resolver_coderef) {
                die "Can't locate function $user_supplied_resolver via class $class_name during creation of inline data source";
            }
        } else {
            $class->error_message("The data_source specified 'required_for_get', but the file resolver was not a coderef or function name");
            return;
        }
    } else {
        my $resolve_path_with = $ds_data->{'resolve_path_with'} || $ds_data->{'path'} ||
                                $ds_data->{'server'} || $ds_data->{'file_resolver'};
        unless ($resolve_path_with or $ds_data->{'file_list'}) {
           $class->error_message("A data_source's definition must include 'resolve_path_with', 'path', 'server', or 'file_list'");
           return;
        }

        if (! ref($resolve_path_with)) {
            # a simple string
            if ($class_name->can($resolve_path_with) or grep { $_ eq $resolve_path_with } @{$class_data->{'has'}}) {
               # a method or property name
               no strict 'refs';
               $path_resolver_coderef = \&{ $class_name . "::$resolve_path_with"};
            } else {
               # a hardcoded pathname
               $path_resolver_coderef = sub { $resolve_path_with };
            }
        } elsif (ref($resolve_path_with) eq 'CODE') {
            $path_resolver_coderef = $resolve_path_with;

        } elsif (ref($resolve_path_with) ne 'ARRAY') {
            $class->error_message("A data_source's 'resolve_path_with' must be a coderef, arrayref, pathname or method name");
            return;

        } elsif (ref($resolve_path_with) eq 'ARRAY') {
            # A list of things
            if (ref($resolve_path_with->[0]) eq 'CODE') {
                # A coderef, then property list
                @required_for_get = @{$ds_data->{'resolve_path_with'}};
                $path_resolver_coderef = shift @required_for_get;

            } elsif (grep { $_ eq $resolve_path_with->[0] }
                          keys(%{$class_data->{'has'}})      ) {
                # a list of property names, join them with /s
                unless ($ds_data->{'base_path'}) {
                    $class->warning_message("$class_name inline data source: 'resolve_path_with' is a list of method names, but 'base_path' is undefined'");
                }
                @required_for_get = @{$resolve_path_with};
                my $base_path = $ds_data->{'base_path'};
                $path_resolver_coderef = sub { no warnings 'uninitialized';
                                              return join('/', $base_path, @_)
                                            };
 
            } elsif ($class_name->can($resolve_path_with->[0])) {
                # a method compiled into the class, but not one that's a property
                @required_for_get = @{$resolve_path_with};
                my $fcn_name = shift @required_for_get;
                my $path_resolver_coderef = $class_name->can($fcn_name);
                unless ($path_resolver_coderef) {
                    die "Can't locate function $fcn_name via class $class_name during creation of inline data source";
                }

            } elsif (! ref($resolve_path_with->[0])) {
                # treat the first element as a sprintf format
                @required_for_get = @{$resolve_path_with};
                my $format = shift @required_for_get;
                $path_resolver_coderef = sub { no warnings 'uninitialized';
                                               return sprintf($format, @_);
                                             };
            } else {
                $class->error_message("Unrecognized layout for 'resolve_path_with'");
                return;
            }
        } else {
            $DB::single=1;
            $class->error_message("Unrecognized layout for 'resolve_path_with'");
            return;
        }
    }

    return ($path_resolver_coderef, @required_for_get);
}


# Properties we'll copy from $self when creating a concrete data source
sub _common_params_for_concrete_data_sources {
    my $self = shift;

    my %params;
    foreach my $param ( qw( delimiter skip_first_line column_order sort_order record_separator constant_values ) ) {
        next unless defined $self->$param;
        my @vals = $self->$param;
        if (@vals > 1) {
            $params{$param} = \@vals;
        } else {
            $params{$param} = $vals[0];
        }
    }
    return %params;
}
        

sub initializer_should_create_column_name_for_class_properties {
    1;
}
    
# Called by the class initializer 
sub create_from_inline_class_data {
    my($class, $class_data, $ds_data) = @_;

    unless ($ds_data->{'column_order'}) {
        die "Can't create inline data source for ".$class_data->{'class_name'}.": 'column_order' is a required param";
    }


    my($file_resolver, @required_for_get) = $class->_normalize_file_resolver_details($class_data, $ds_data);
    return unless $file_resolver;

    if (!exists($ds_data->{'constant_values'}) and @required_for_get) {
        # If there are required_for_get params, but the user didn't specify any constant_values,
        # then all the required_for_get items that are real properties become constant_values
        $ds_data->{'constant_values'} = [];
        my %columns_from_ds = map { $_ => 1 } @{$ds_data->{'column_order'}};

        foreach my $param_name ( @required_for_get ) {
            my $param_data = $class_data->{'has'}->{$param_name};
            next unless $param_data;

            my $param_column = $param_data->{'column_name'};
            next unless $param_column;

            unless ($columns_from_ds{$param_column}) {
                push @{$ds_data->{'constant_values'}}, $param_name;
            }
        }
    }


    my %ds_creation_params;
    foreach my $param ( qw( delimiter record_separator column_order cache_size skip_first_line sort_order constant_values ) ) {
        if (exists $ds_data->{$param}) {
            $ds_creation_params{$param} = $ds_data->{$param};
        }
    }

    my($namespace, $class_name) = ($class_data->{'class_name'} =~ m/^(\w+?)::(.*)/);
    my $ds_id = "${namespace}::DataSource::${class_name}";
    my $ds_type = delete $ds_data->{'is'};
 
    my $ds = $ds_type->create(
        %ds_creation_params,
        id => $ds_id,
        required_for_get => \@required_for_get,
        file_resolver => $file_resolver
    );

    return $ds;
}
        

1;

=pod

=head1 NAME

UR::DataSource::FileMux - Parent class for datasources which can multiplex many files together

=head1 SYNOPSIS

  package MyNamespace::DataSource::MyFileMux;
  class MyNamespace::DataSource::MyFileMux {
      is => ['UR::DataSource::FileMux', 'UR::Singleton'],
  };
  sub column_order { ['thing_id', 'thing_name', 'thing_color'] }
  sub sort_order { ['thing_id'] }
  sub delimiter { "\t" }
  sub constant_values { ['thing_type'] }
  sub required_for_get { ['thing_type'] }
  sub file_resolver {
      my $thing_type = shift;
      return '/base/path/to/files/' . $thing_type;
  }

  package main;
  class MyNamespace::ThingMux {
      id_by => ['thing_id', 'thing_type' ],
      has => ['thing_id', 'thing_type', 'thing_name','thing_color'],
      data_source => 'MyNamespace::DataSource::MyFileMux',
  };

  my @objs = MyNamespace::Thing->get(thing_type => 'people', thing_name => 'Bob');

=head1 DESCRIPTION

UR::DataSource::FileMux provides a framework for file-based data sources where the
data files are split up between one or more parameters of the class.  For example,
in the synopsis above, the data for the class is stored in several files in the
directory /base/path/to/files/.  Each file may have a name such as 'people' and 'cars'.

When a get() request is made on the class, the parameter 'thing_type' must be present
in the rule, and the value of that parameter is used to complete the file's pathname,
via the file_resolver() function.  Note that even though the 'thing_type' parameter
is not actually stored in the file, its value for the loaded objects gets filled in
because that paremeter exists in the constant_values() configuration list, and in
the get() request.

=head2 Configuration

These methods determine the configuration for your data source and should appear as
properties of the data source or as functions in the package.

=over 4

=item delimiter()

=item record_separator()

=item skip_first_line()

=item column_order()

=item sort_order()

These configuration items behave the same as in a UR::DataSource::File-based data source.

=item required_for_get()

required_for_get() should return a listref of parameter names.  Whenever a get() request is
made on the class, the listed parameters must appear in the rule, or be derivable via
UR::Context::infer_property_value_from_rule().  

=item file_resolver()

file_resolver() is called as a function (not a method).  It should accept the same number
of parameters as are mentioned in required_for_get().  When a get() request is made,
those named parameters are extracted from the rule and passed in to the file_resolver()
function in the same order.  file_resolver() must return a string that is used as the
pathname to the file that contains the needed data.  The function must not have any
other side effects.

In the case where the data source is a regular object (not a UR::Singleton'), then 
the file_resover parameter should return a coderef.

=item constant_values()

constant_values() should return a listref of parameter names.  These parameter names are used by
the object loader system to fill in data that may not be present in the data files.  If the
class has parameters that are not actually stored in the data files, then the parameter
values are extracted from the rule and stored in the loaded object instances before being
returned to the user.  

In the synopsis above, thing_type is not stored in the data files, even though it exists
as a parameter of the MyNamespace::ThingMux class.

=back

=head2 Theory of Operation

As part of the data-loading infrastructure inside UR, the parameters in a get() 
request are transformed into a UR::BoolExpr instance, also called a rule.  
UR::DataSource::FilMux hooks into that infrastructure by implementing
create_iterator_closure_for_rule().  It first collects the values for all the
parameters mentioned in required_for_get() by passing the rule and needed
parameter to infer_property_value_from_rule() of the current Context.  If any
of the needed parameters is not resolvable, an excpetion is raised.

Some of the rule's parameters may have multiple values.  In those cases, all the 
combinations of values are expanded.  For example of param_a has 2 values, and
param_b has 3 values, then there are 6 possible combinations.

For each combination of values, the file_resolver() function is called and 
returns a pathname.  For each pathname, a file-specific data source is created
(if it does not already exist), the server() configuration parameter created
to return that pathname.  Other parameters are copied from the values in the
FileMux data source, such as column_names and delimiter.
create_iterator_closure_for_rule() is called on each of those data sources.

Finally, an iterator is created to wrap all of those iterators, and is returned.
  
=head1 INHERITANCE

UR::DataSource

=head1 SEE ALSO

UR, UR::DataSource, UR::DataSource::File

=head1 AUTHOR

Anthony Brummett <abrummet@watson.wustl.edu>


=cut

