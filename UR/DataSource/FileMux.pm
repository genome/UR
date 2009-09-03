package UR::DataSource::FileMux;

use UR;
use strict;
use warnings;

use Sub::Name ();
use Sub::Install ();

class UR::DataSource::FileMux {
    is => ['UR::DataSource'],
    doc => 'A factory for other datasource factories that is able to pivot depending on parameters in the rule used for get()',
};


# The file-specific parent data source classes will inherit from this one
sub _delegate_data_source_class {
    'UR::DataSource::File';
}


# Called by the class initializer 
sub create_from_inline_class_data {
    my($self, $class_data, $ds_data) = @_;

    my($namespace, $class_name) = ($class_data->{'class_name'} =~ m/^(\w+)::(.*)/);
    my $ds_name = "${namespace}::DataSource::${class_name}";

    my $ds_meta = UR::Object::Type->get($ds_name);
    if ($ds_meta) {
        $self->error_message($class_data->{'class_name'}.": Created/In-line data_source resolves to a data source that already exists ($ds_name)");
        return;
    }

    # Define the class for the mux data source
    my $mux_ds_meta = UR::Object::Type->define(
        class_name => $ds_name,
        is => __PACKAGE__,
    );
    unless ($mux_ds_meta) {
        $self->error_message("Can't create inline data source class $ds_name");
        return;
    }

    my($path_resolver_closure, @required_for_get) = $self->_normalize_file_resolver_details($ds_name,$class_data, $ds_data);
    return unless $path_resolver_closure;

    # This creates a class that all the file specific data sources inherit from.  This class collects
    # the configuration data like delimiter, column_order, etc
    my $file_specific_parent_ds_name = $ds_name->_file_specific_parent_ds_name;
    $self->_define_file_specific_data_source_parent(
        $file_specific_parent_ds_name,
        $self->_delegate_data_source_class,
        $ds_data,
    );

    unless ($ds_meta = UR::Object::Type->get($ds_name)) {
        $self->error_message($class_data->{'class_name'}.": Failed to create inline data source");
        return;
    }

    my @constant_values;
    if (exists($ds_data->{'constant_values'})) {
        if (ref($ds_data->{'constant_values'}) eq 'ARRAY'  and  scalar(@{$ds_data->{'constant_values'}})) {
            @constant_values = @{$ds_data->{'constant_values'}};
        } elsif(! ref($ds_data->{'constant_values'})) {
            @constant_values = ( $ds_data->{'constant_values'} );
        } else {
            $self->error_message("A data_source's constant_values must be a scalar or arrayref");
            return;
        }

    } elsif (@required_for_get) {
        my %columns_from_ds = map { $_ => 1 } $file_specific_parent_ds_name->column_order;

        foreach my $param_name ( @required_for_get ) {
            my $param_data = $class_data->{'has'}->{$param_name};
            next unless $param_data;

            my $param_column = $param_data->{'column_name'};
            next unless $param_column;

            unless ($columns_from_ds{$param_column}) {
                push @constant_values, $param_name;
            }
        }
    }

    if (@constant_values) { 
        my $const_sub = sub { @constant_values };
        Sub::Name::subname "${file_specific_parent_ds_name}::constant_values" => $const_sub;
        Sub::Install::reinstall_sub({
            into => $file_specific_parent_ds_name,
            as   => 'constant_values',
            code => $const_sub,
        });
        $self->_setup_generate_load_tmpl_method($file_specific_parent_ds_name, \@constant_values);
    }

    if (@required_for_get) {
        my $required_sub = sub { @required_for_get };
        Sub::Name::subname "${ds_name}::required_for_get" => $required_sub;
        Sub::Install::reinstall_sub({
            into => $ds_name,
            as   => 'required_for_get',
            code => $required_sub,
        });
    }

    Sub::Install::install_sub({
               into => $ds_name,
               as   => 'file_resolver',
               code => $path_resolver_closure,
    });

    return $ds_name;
}

 
# All the concrete, file-specific data sources will inherit from this class.  This is where we'll
# put configuration information line delimiter, column_order, etc.
sub _file_specific_parent_ds_name {
    return $_[0] . '::_Parent';
}


my %WORKING_RULES; # Avoid recusion when infering values from rules
sub create_iterator_closure_for_rule {
        my($self,$rule) = @_;

        if ($WORKING_RULES{$rule->id}++) {
            my $subject_class = $rule->subject_class_name;
            $self->error_message("Recursive entry into create_iterator_closure_for_rule() for class $subject_class rule_id ".$rule->id);
            $WORKING_RULES{$rule->id}--;
            return;
        }

        my $context = UR::Context->get_current;
        my @required_for_get = $self->required_for_get;
        my @all_resolver_params;
        for(my $i = 0; $i < @required_for_get; $i++) {
            my $param_name = $required_for_get[$i];
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

        unless (UR::Object::Type->get($self->_file_specific_parent_ds_name)) {
            $self->_define_file_specific_data_source_parent($self->_file_specific_parent_ds_name,
                                                            $self->_delegate_data_source_class);
        }

        # Each combination of params ends up being from a different data source.  Make an
        # iterator pulling from each of them
        my @data_source_iterators;
        my $file_resolver = $self->can('file_resolver');   # This will be called as a regular function, not a method!
        foreach my $resolver_params ( @resolver_param_combinations ) {

            my @sub_ds_name_parts;
            my $this_ds_rule_params = $rule->legacy_params_hash;
            for (my $i = 0; $i < @required_for_get; $i++) {
                push @sub_ds_name_parts, $required_for_get[$i] . $resolver_params->[$i];
                $this_ds_rule_params->{$required_for_get[$i]} = $resolver_params->[$i];
            }
            my $sub_ds_name = join('::', $self, @sub_ds_name_parts);

            my $sub_data_source_creator_closure = sub {
                my $file_path = $file_resolver->(@_);
                unless (defined $file_path) {
                    die "Can't resolve data source: resolver for " .
                        $rule->subject_class_name .
                        " returned undef for params " . join(',',@_);
                }
                # FIXME - when this is a proper property of a data sources, move it there...
                Sub::Install::install_sub({
                    into => $sub_ds_name,
                    as   => 'server',
                    code => sub { $file_path },
                });
                UR::Object::Type->define(
                    class_name => $sub_ds_name,
                    is => $self->_file_specific_parent_ds_name,
                );
            };

            my $ds = UR::Object::Type->get($sub_ds_name);
            unless ($ds) {
                $sub_data_source_creator_closure->(@$resolver_params);
            }

            my $this_ds_rule = UR::BoolExpr->resolve_for_class_and_params($rule->subject_class_name,%$this_ds_rule_params);
            push @data_source_iterators, $sub_ds_name->create_iterator_closure_for_rule($this_ds_rule);
        }
        delete $WORKING_RULES{$rule->id};

        # If we only made 1 (or 0), just return that one directly
        return $data_source_iterators[0] if (@data_source_iterators < 2);

        # Results are coming from more than one data source.  Make an iterator encompassing all of them
        my $iterator = sub {
            while (@data_source_iterators) {
                while (my $thing = $data_source_iterators[0]->()) {
                    return $thing;
                }
                shift @data_source_iterators;
            }

            return;
        };
        return $iterator;
}


sub _generate_template_data_for_loading {
    my $self = shift;
    my $delegate_class = $self->_file_specific_parent_ds_name();
    return $delegate_class->_generate_template_data_for_loading(@_);
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
    my($self, $ds_name, $class_data, $ds_data) = @_;

    my $path_resolver_closure;
    my @required_for_get;

    if (exists $ds_data->{'required_for_get'}) {
        @required_for_get = @{$ds_data->{'required_for_get'}};
        my $user_supplied_resolver = $ds_data->{'file_resolver'} || $ds_data->{'resolve_file_with'} ||
                                     $ds_data->{'resolve_path_with'};
        if (ref($user_supplied_resolver) eq 'CODE') {
            $path_resolver_closure = $user_supplied_resolver;
        } elsif (! ref($user_supplied_resolver)) {
            # It's a method name
            $path_resolver_closure = sub { $ds_name->$user_supplied_resolver(@_); };
        } else {
            $self->error_message("The data_source specified 'required_for_get', but the file resolver was not a coderef or method name");
            return;
        }
    } else {
        my $resolve_path_with = $ds_data->{'resolve_path_with'} || $ds_data->{'path'} ||
                                $ds_data->{'server'} || $ds_data->{'file_resolver'};
        unless ($resolve_path_with or $ds_data->{'file_list'}) {
           $self->error_message("A data_source's definition must include 'resolve_path_with', 'path', 'server', or 'file_list'");
           return;
        }

        if (! ref($resolve_path_with)) {
            # a simple string
            if ($ds_name->can($resolve_path_with) or grep { $_ eq $resolve_path_with } @{$class_data->{'has'}}) {
               # a method or property name
               $path_resolver_closure = sub { $ds_name->$resolve_path_with(@_) };
            } else {
               # a hardcoded pathname
               $path_resolver_closure = sub { $resolve_path_with };
            }
        } elsif (ref($resolve_path_with) eq 'CODE') {
            $path_resolver_closure = $resolve_path_with;

        } elsif (ref($resolve_path_with) ne 'ARRAY') {
            $self->error_message("A data_source's 'resolve_path_with' must be a coderef, arrayref, pathname or method name");
            return;

        } elsif (ref($resolve_path_with) eq 'ARRAY') {
            # A list of things
            if (ref($resolve_path_with->[0]) eq 'CODE') {
                # A coderef, then property list
                @required_for_get = @{$ds_data->{'resolve_path_with'}};
                $path_resolver_closure = shift @required_for_get;

            } elsif ($ds_name->can($resolve_path_with->[0])) {
                # a method compiled into the class (not a property! Their subs haven't been created yet)
                @required_for_get = @{$resolve_path_with};
                my $sub = $ds_name->can(shift @required_for_get);
                # call it as a method
                $path_resolver_closure = sub { unshift @_, $ds_name; goto $sub; };

            } elsif (grep { $_ eq $resolve_path_with->[0] }
                          keys(%{$class_data->{'has'}})      ) {
                # a list of property names, join them with /s
                unless ($ds_data->{'base_path'}) {
                    $self->warning_message("$ds_name 'resolve_path_with' is a list of method names, but 'base_path' is undefined'");
                }
                @required_for_get = @{$resolve_path_with};
                my $base_path = $ds_data->{'base_path'};
                $path_resolver_closure = sub { no warnings 'uninitialized';
                                              return join('/', $base_path, @_)
                                            };
            } elsif (! ref($resolve_path_with->[0])) {
                # treat the first element as a sprintf format
                @required_for_get = @{$resolve_path_with};
                my $format = shift @required_for_get;
                $path_resolver_closure = sub { no warnings 'uninitialized';
                                               return sprintf($format, @_);
                                             };
            } else {
                $self->error_message("Unrecognized layout for 'resolve_path_with'");
                return;
            }
        } else {
            $DB::single=1;
            $self->error_message("Unrecognized layout for 'resolve_path_with'");
            return;
        }
    }

    return ($path_resolver_closure, @required_for_get);
}



sub _define_file_specific_data_source_parent {
    my($self,$ds_name, $parent_ds_name, $ds_data) = @_;

    my $ds_meta = UR::Object::Type->define(
        class_name => $ds_name,
        is => $parent_ds_name,
    );
    unless ($ds_meta) {
        $self->error_message("Can't create class $ds_name");
        return;
    }

    foreach my $param_name ( qw( delimiter skip_first_line file_list column_order sort_order is_sorted record_separator ) ) {
        my $sub;
        if ($ds_data) {
            if (ref($ds_data->{$param_name}) eq 'ARRAY') {
                my @data = @{$ds_data->{$param_name}};
                $sub = sub { @data };
            } elsif ($ds_data->{$param_name}) {
                my $data = $ds_data->{$param_name};
                $sub = sub { $data };
            }
        } else {
            $sub = $self->can($param_name);
        }

        if ($sub) {
            Sub::Name::subname "${ds_name}::${param_name}" => $sub;
            Sub::Install::install_sub({
                into => $ds_name,
                as   => $param_name,
                code => $sub,
            });
        }
    }


    my $constant_values;
    if ($ds_data->{'constant_values'}) {
        if (ref($ds_data->{'constant_values'}) eq 'ARRAY') {
            $constant_values = $ds_data->{'constant_values'};
        } else {
            $constant_values = [ $ds_data->{'constant_values'} ];
        }
    } elsif ($self->can('constant_values')) {
        $constant_values = [ $self->constant_values ];
    }
    if ($constant_values) {
        $self->_setup_generate_load_tmpl_method($ds_name,$constant_values);
    }
 
    return $ds_name;    
}


sub _setup_generate_load_tmpl_method {
    my($self,$target_class,$constant_values) = @_;

    return unless(ref($constant_values) eq 'ARRAY');

    my $gen_templates = sub {
        my $self = $_[0];
        my $subref = $self->super_can('_generate_loading_templates_arrayref');
        my $templates = $subref->(@_);
        $templates->[0]->{'constant_property_names'} = $constant_values;
        return $templates;
    };

    Sub::Name::subname "${target_class}::_generate_loading_templates_arrayref" => $gen_templates;
    Sub::Install::reinstall_sub({
        into => $target_class,
        as   => '_generate_loading_templates_arrayref',
        code => $gen_templates,
    });
}
    
 
1;

=pod

=head1 NAME

UR::DataSource::FileMux - Parent class for datasources which can multiplex many files together

=head1 SYNOPSIS

  package MyNamespace::DataSource::MyFileMux;
  class MyNamespace::DataSource::MyFileMux {
      is => ['UR::DataSource::FileMux'],
  };
  sub column_order { qw( thing_id thing_name thing_color ) }
  sub sort_order { qw( thing_id ) }
  sub delimiter { "\t" }
  sub constant_values { qw( thing_type ) }
  sub required_for_get { qw( thing_type ) }
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

These methods determine the configuration for your data source.  They should require no arguments.

=over 4

=item delimiter()

=item record_separator()

=item skip_first_line()

=item column_order()

=item sort_order()

These configuration items behave the same as in a UR::DataSource::File-based data source.

=item required_for_get()

required_for_get() should return a list of parameter names.  Whenever a get() request is
made on the class, the listed parameters must appear in the rule, or be derivable via
UR::Context::infer_property_value_from_rule().  

=item file_resolver()

file_resolver() is called as a function (not a method).  It should accept the same number
of parameters as are mentioned in required_for_get().  When a get() request is made,
those named parameters are extracted from the rule and passed in to the file_resolver()
function in the same order.  file_resolver() must return a string that is used as the
pathname to the file that contains the needed data.

=item constant_values()

constant_values() should return a list of parameter names.  These parameter names are used by
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

If it does not already exist, a class (called the file-specific data source parent)
is created, inheriting from UR::DataSource::File, and all the configuration
parameters needed for UR::DataSource::File are copied from the user's data source
to this parent class - all parameters except server().

Some of the rule's parameters may have multiple values.  In those cases, all the 
combinations of values are expanded.  For example of param_a has 2 values, and
param_b has 3 values, then there are 6 possible combinations.

For each combination of values, the file_resolver() function is called and 
returns a pathname.  For each pathname, a file-specific data source is created
(if it does not already exist), the server() configuration parameter created
to return that pathname.  This data source inherits from the file-specific
data source parent so as to return all the other configuration parameters.
create_iterator_closure_for_rule() is called on each of those data sources.

Finally, an iterator is created to wrap all of those iterators, and is returned.
  
=head1 INHERITANCE

UR::DataSource

=head1 SEE ALSO

UR, UR::DataSource, UR::DataSource::File

=head1 AUTHOR

Anthony Brummett <abrummet@watson.wustl.edu>


=cut

