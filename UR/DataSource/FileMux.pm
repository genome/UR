package UR::DataSource::FileMux;

use UR;
use strict;
use warnings;

use Sub::Name ();
use Sub::Install ();

class UR::DataSource::FileMux {
    is => ['UR::DataSource', 'UR::Singleton'],
    doc => 'A factory for other datasource factories that is able to pivot depending on parameters in the rule used for get()',
};




# Called by the class initializer 
sub create_from_inline_class_data {
    my($self, $class_data, $ds_data) = @_;

    my($namespace, $class_name) = ($class_data->{'class_name'} =~ m/^(\w+)::(.*)/);
    my $ds_name = "${namespace}::DataSource::${class_name}";

$DB::single=1;
    my $ds_meta = UR::Object::Type->get($ds_name);
    if ($ds_meta) {
        $self->error_message($class_data->{'class_name'}.": Created/In-line data_source resolves to a data source that already exists ($ds_name)");
        return;
    }
    my($path_resolver_closure, @required_for_get) = $self->_derive_file_resolver_details($ds_name,$class_data, $ds_data);
    return unless $path_resolver_closure;

    my $created_ds_name = UR::DataSource::SortedCsvFile->create_from_inline_class_data(
        $class_data,
        {   
            delimiter       => $ds_data->{'delimiter'},
            skip_first_line => $ds_data->{'skip_first_line'},
            file_list       => $ds_data->{'file_list'},
            column_order    => $ds_data->{'column_order'},
            sort_order      => $ds_data->{'sort_order'},
            is_sorted       => $ds_data->{'is_sorted'},
            sort_order      => $ds_data->{'sort_order'},
         }
    );

    if ($created_ds_name ne $ds_name) {
        $self->error_message("delegated create_from_inline_class_data() returned $created_ds_name, expected $ds_name");
        return;
    }
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
        my %columns_from_ds = map { $_ => 1 } $created_ds_name->column_order;

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
        Sub::Name::subname "${ds_name}::constant_values" => $const_sub;
        Sub::Install::reinstall_sub({
            into => $ds_name,
            as   => 'constant_values',
            code => $const_sub,
        });

        my $gen_templates = sub {
            my $self = $_[0];
            my $subref = $self->super_can('_generate_loading_templates_arrayref');
            my $templates = $subref->(@_);
            $templates->[0]->{'constant_property_names'} = \@constant_values;
            return $templates;
        };
        
        Sub::Name::subname "${ds_name}::_generate_loading_templates_arrayref" => $gen_templates;
        Sub::Install::reinstall_sub({
            into => $ds_name,
            as   => '_generate_loading_templates_arrayref',
            code => $gen_templates,
        });
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

    Sub::Install::install_sub({
               into => $ds_name,
               as   => 'create_iterator_closure_for_rule',
               code => \&_factory_create_iterator_closure_for_rule,
    });
    
    return $ds_name;
}



my %WORKING_RULES; # Avoid recusion when infering values from rules
# This ends up getting installed into the class' factory data_source as create_iterator_closure_for_rule
# It's job is to examine the rule, create file-specific data sources if they don't exist yet, and
# call create_iterator_closure_for_rule() on those file-specific DSs
sub _factory_create_iterator_closure_for_rule {
        my($self,$rule) = @_;

$DB::single=1;
        #if ($self ne $ds_name) {
        #    # The file-specific data sources inherit from the class' data source factory class
        #    # which means create_iterator_closure_for_rule() gets us here for both cases of 
        #    # when we need to create a file-specific DS, or when those specific DSs need to retrieve
        #    # data.  We can differentiate those cases when $self ne $ds_name ($ds_name will be the
        #    # class' DS factory).  If we're a file-specific DS, kick control up the chain.
        #    # Seems a big hack...
        #    return UR::DataSource::SortedCsvFile::create_iterator_closure_for_rule($self,$rule);
        #}

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
                my $c=UR::Object::Type->define(
                    class_name => $sub_ds_name,
                    is => $self,
                );
                # FIXME - ugly hack!  This is necessary because the file-specific data sources inherit from
                # the class' DS factory (which inherits from the File data_source).  The factory's 
                # resolve_iterator_closure_for_rule() needs to create file-specific DSs, but the file-specific
                # DSs need to inherit resolve_iterator_closure_for_rule() from UR::DataSource::SortedCsvFile so
                # they can read the actual file
                Sub::Install::install_sub({
                    into => $sub_ds_name,
                    as => 'create_iterator_closure_for_rule',
                    code => \&UR::DataSource::SortedCsvFile::create_iterator_closure_for_rule,
                });
                1;
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


sub _derive_file_resolver_details {
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
                    
 
1;
