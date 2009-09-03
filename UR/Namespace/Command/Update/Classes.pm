
package UR::Namespace::Command::Update::Classes;

use strict;
use warnings;
use UR;
use Text::Diff;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command::RunsOnModulesInTree',
    has => [
        data_source                 => { is => 'List',      is_optional => 1, doc => 'Limit updates to these data sources' },        
        force_check_all_tables      => { is => 'Boolean',   is_optional => 1, doc => 'By default we only look at tables with a new DDL time for changed database schema information.  This explicitly (slowly) checks each table against our cache.' },
        force_rewrite_all_classes   => { is => 'Boolean',   is_optional => 1, doc => 'By default we only rewrite classes where there are database changes.  Set this flag to rewrite all classes even where there are no schema changes.' },
        table_name                  => { is => 'List',      is_optional => 1, doc => 'Update the specified table.' },
        class_name                  => { is => 'List',      is_optional => 1, doc => 'Update only the specified classes.' },
    ],
);

sub help_brief {
    "Update table definitions and class definitions to reflect changes in the remote data dictionary."
}

sub help_detail {
    return <<EOS;

Reads from the data sources in the current working directory's namespace,
and updates the local class tree.

This hits the data dictionary for the remote database, and gets changes there
first.  Those changes are then used to mutate the class tree.

If specific data sources are specified on the command-line, it will limit
its database examination to just data in those data sources.  This command
will, however, always load ALL classes in the namespace when doing this update,
to find classes which currently reference the updated table, or are connected
to its class indirectly.

EOS
}



sub create {
    my($class,%params) = @_;

    for my $param_name (qw/data_source class_name table_name/) {
        if (exists $params{$param_name} && ! ref($params{$param_name})) {
            # Make sure the data_source parameter is always a listref, even if there's only one item
            $params{$param_name} = [ $params{$param_name} ];
        }
    }

    # This is used by the test case to turn on no-commit for the metadata DB,
    # but still have _sync_filesystem write out the modules
    my $override = delete $params{'_override_no_commit_for_filesystem_items'};

    my $obj =  $class->SUPER::create(%params);
    return unless $obj;

    $obj->{'_override_no_commit_for_filesystem_items'} = $override if $override;

    return $obj;
}


our @dd_classes = (
    'UR::DataSource::RDBMS::Table',
    'UR::DataSource::RDBMS::TableColumn',
    'UR::DataSource::RDBMS::FkConstraint',
    'UR::DataSource::RDBMS::Table::Ghost',
    'UR::DataSource::RDBMS::TableColumn::Ghost',
    'UR::DataSource::RDBMS::FkConstraint::Ghost',
);    

sub execute {
    my $self = shift;

    #
    # Command parameter checking
    #
    
    my $force_check_all_tables = $self->force_check_all_tables;
    my $force_rewrite_all_classes = $self->force_rewrite_all_classes;
    
    # Hack because some parts of the schema are only visible to the rw user.
    my $access_level_param = UR::Command::Param->get(command_id => 'main', name => 'access');
    if ($access_level_param) {
        my $access_level = $access_level_param->value;
        unless (defined $access_level and $access_level eq "rw") {
            $access_level_param->value("rw");
        }
    }

    if (@{ $self->bare_args }) {
        $self->error_message("Bare paramters not supported: @{ $self->bare_args }\n");
        $self->status_message($self->help_usage_complete_text,"\n");
        return;
    }

    $self->_init;

    my $namespace = $self->namespace_name;
    unless ($namespace) {
        $self->error_message("This command must be run from a namespace directory.");
        return;
    }
    $self->status_message("Updating namespace: $namespace\n");

    my @namespace_data_sources = $namespace->get_data_sources;

    my $specified_table_name_arrayref = $self->table_name;
    my $specified_data_source_arrayref = $self->data_source;
    my $specified_class_name_arrayref = $self->class_name;
   
 
    my @data_dictionary_objects;
    
    if ($specified_class_name_arrayref or $specified_table_name_arrayref) {
        my $ds_table_list;
        if ($specified_class_name_arrayref) {
            $ds_table_list = [
                map { [$_->data_source, $_->table_name] }
                map { $_->get_class_object } 
                @$specified_class_name_arrayref
            ];        
        }
        else {
            $ds_table_list = [
                map { [$_->data_source, $_->table_name] }
                UR::DataSource::RDBMS::Table->get(table_name => $specified_table_name_arrayref)
            ];
            for my $item (@$ds_table_list) {
                UR::Object::Type->get(data_source => $item->[0], table_name => $item->[1]);
            }
        }
        
        for my $item (@$ds_table_list) {
            my ($data_source, $table_name) = @$item;
            for my $dd_class (qw/UR::DataSource::RDBMS::Table UR::DataSource::RDBMS::FkConstraint UR::DataSource::RDBMS::TableColumn/) {
                push @data_dictionary_objects,
                    $dd_class->get(data_source => $data_source, table_name => $table_name);
            }
        }
    }
    else {
        # Do the update by data source, all or whatever is specified.
        
        #
        # Determine which data sources to update from.
        # By default, we do all datasources owned by the namespace.
        #
        
        my @target_data_sources;
        if ($specified_data_source_arrayref) {
            @target_data_sources = ();
            my %data_source_is_specified = map { $_ => 1 } @$specified_data_source_arrayref;
            for my $ds (@namespace_data_sources) {
                if ($data_source_is_specified{$ds}) {
                    push @target_data_sources, $ds;
                }
            }
            delete @data_source_is_specified{@namespace_data_sources};
            if (my @unknown = keys %data_source_is_specified) {
                $self->error_message(
                    "Unknown data source(s) for namespace $namespace: @unknown!\n"
                    . "Select from:\n"
                    . join("\n",@namespace_data_sources)
                    . "\n"
                );
                return;
            }
        } else {
            # Don't update the Meta datasource, unless they specificly asked for it
            @target_data_sources = grep { $_ !~ /::Meta$/ } @namespace_data_sources;
        }
        
        $self->status_message("Found data sources: " 
            .   join(", " , 
                    map { /${namespace}::DataSource::(.*)$/; $1 || $_ } 
                    @target_data_sources
                )
        );
        
        #
        # A copy of the database metadata is in the ::Meta sqlite datasource.
        # Get updates to it first.
        #
        
        #$DB::single=1;
        
        for my $data_source (@target_data_sources) {
            # ensure the class has been lazy-loaded until UNIVERSAL::can is smarter...
            $data_source->class;
            $self->status_message("Checking $data_source for schema changes ...");
            my $success =
                $self->_update_database_metadata_objects_for_schema_changes(
                    data_source => $data_source,
                    force_check_all_tables => $force_check_all_tables,
                );
            unless ($success) {
                return;
            }
        }
    
        #
        # Summarize the database changes by table.  We'll create/update/delete the class which goes with that table.
        #
    
        #$DB::single = 1;
    
        for my $dd_class (qw/UR::DataSource::RDBMS::Table UR::DataSource::RDBMS::FkConstraint UR::DataSource::RDBMS::TableColumn/) {
            push @data_dictionary_objects, 
                grep { $force_rewrite_all_classes ? 1 : $_->changed } 
                $dd_class->all_objects_loaded;
    
            my $ghost_class = $dd_class . "::Ghost";
            push @data_dictionary_objects, $ghost_class->all_objects_loaded;
        }
        
    }
    
    # The @data_dictionary_objects array has all dd meta which should be used to rewrite classes.
    
    my %changed_tables;    
    for my $obj (
        @data_dictionary_objects
    ) {
        my $table;
        if ($obj->can("get_table")) {
            $table = $obj->get_table;
            unless ($table) {
                Carp::confess("No table object for $obj" . $obj->id);
            }
        }
        elsif ($obj->isa("UR::DataSource::RDBMS::Table") or $obj->isa("UR::DataSource::RDBMS::Table::Ghost")) {
            $table = $obj
        }
        # we may find no table if it was dropped, and this is one of its old cols/constraints
        next unless $table;

        $changed_tables{$table->id} = 1;
    }


    # Some ill-behaved modules might set no_commit to true at compile time.
    # Reset it back to whatever it is now after going through the namespace's modules
    # Note that when we have class info in the metadata DB, this probably won't be
    # necessary anymore since we won't have to actually load up the .pm files to 
    # discover classes in the namespace
    
    my $remembered_no_commit_setting = UR::DBI->no_commit(); 


    #
    # Update the classes based-on changes to the database schemas
    #

    #$DB::single = 1;

    if (@data_dictionary_objects) {
        $self->status_message("Found " . keys(%changed_tables) . " tables with changes.") unless $force_rewrite_all_classes;
        $self->status_message("Resolving corresponding class changes...");
        my $success =
            $self->_update_class_metadata_objects_to_match_database_metadata_changes(
                data_dictionary_objects => \@data_dictionary_objects
            );
        unless ($success) {
            return;
        }
    }
    else {
        $self->status_message("No data schema changes.");
    }

    UR::DBI->no_commit($remembered_no_commit_setting);


    #
    # The namespace module may have special rules for creating classes from regular (non-schema) data.
    # At this point we allow the namespace to adjust the class tree as it chooses.
    #

    #$DB::single = 1;

    $namespace->class;
    if (
        $namespace->can("_update_classes_from_data_sources") 
        and not $specified_table_name_arrayref 
        and not $specified_class_name_arrayref
        and not $specified_data_source_arrayref
    ) {
        $self->status_message("Checking for custom changes for the $namespace namespace...");
        $namespace->_update_classes_from_data_sources();
    }

    $self->status_message("Saving metadata changes...");
    my $sync_success = UR::Context->_sync_databases();
    unless ($sync_success) {
        #$DB::single=1;
        $self->error_message("Metadata sync_database failed");
        UR::Context->_rollback_databases();
        return;
    }

    # 
    # Re-write the class headers for changed classes.
    # Output a summary report of what has been changed.
    # This block of logic shold be part of saving class data.
    # Right now, it's done with a _load() override, no data_source, and this block of code. :(
    #

    #$DB::single = 1;

    my @changed_class_meta_objects;
    my %changed_classes;
    my $module_update_success = eval {
        for my $meta_class (qw/
            UR::Object::Type
            UR::Object::Inheritance
            UR::Object::Property
            UR::Object::Property::ID
            UR::Object::Property::Unique
            UR::Object::Reference
            UR::Object::Reference::Property
        /) {
            push @changed_class_meta_objects, grep { $_->changed } $meta_class->all_objects_loaded;

            my $ghost_class = $meta_class . "::Ghost";
            push @changed_class_meta_objects, $ghost_class->all_objects_loaded;
        }

        for my $obj (
            @changed_class_meta_objects
        ) {
            my $class_name = $obj->class_name;
            $changed_classes{$class_name} = 1;
        }
        unless (@changed_class_meta_objects) {
            $self->status_message("No class changes.");
        }

        my $changed_class_count = scalar(keys %changed_classes);
        my $subj = $changed_class_count == 1 ? "class" : "classes";
        $self->status_message("Resolved changes for $changed_class_count $subj");

        $self->status_message("Updating the filesystem...");
        my $success = $self->_sync_filesystem(
            changed_class_names => [sort keys %changed_classes],
        );
        return $success;
    };

    if ($@) {
        $self->error_message("Error updating the filesystem: $@");
        return;
    }
    elsif (!$module_update_success) {
        $self->status_message("Error updating filesystem!");
        return;
    } 
  
    $self->status_message("Filesystem update complete.");
             

    #
    # This commit actually records the data dictionary changes in the ::Meta datasource sqlite database.
    #

    $self->status_message("Committing changes to data sources...");

    unless (UR::Context->_commit_databases()) {
        #$DB::single=1;
        $self->error_message("Metadata commit failed");
        return;
    }


    #
    # The logic below is only necessary if this process is run as part of some larger process.
    # Right now that includes the automated test for this module.
    # After classes have been updated they won't function properly.
    # Ungenerate and re-generate each of the classes we touched, so that it functions according to its new spec.
    # 

    $self->status_message("Cleaning up.");

    my $success = 1;
    for my $class_name (sort keys %changed_classes) {
        my $class_obj = UR::Object::Type->get($class_name);
        next unless $class_obj;
        $class_obj->ungenerate;
        Carp::confess("class $class_name didn't ungenerate properly") if $class_obj->generated;
        unless (eval { $class_obj->generate } ) {
            $self->warning_message("Class $class_name didn't re-generate properly: $@");
            $success = 0;
        }
    }

    unless ($success) {
        $self->status_message("Errors occurred re-generating some classes after update.");
        return;
    }

    #
    # Done
    #

    $self->status_message("Update complete.");
    return 1;
}

#
# The execute() method above is broken into three parts:
#   ->_update_database_metadata_objects_for_schema_changes()
#   ->_update_class_metadata_objects_to_match_database_metadata_changes()
#   ->_sync_filesystem()
#


sub _update_database_metadata_objects_for_schema_changes {
    my ($self, %params) = @_;
    my $data_source = delete $params{data_source};
    my $force_check_all_tables = delete $params{force_check_all_tables};
    die "unknown params " . Dumper(\%params) if keys %params;

    $data_source = $data_source->class;

    my @changed;

    my $last_ddl_time_for_table_name = {};
    if ($data_source->can("get_table_last_ddl_times_by_table_name") and !$force_check_all_tables) {
        # the driver implements a way to get the last DDL time
        $last_ddl_time_for_table_name = $data_source->get_table_last_ddl_times_by_table_name;
    }

    # from the cache of known tables
    my @previous_table_names = $data_source->get_table_names;
    my %previous_table_names = map { $_ => 1 } @previous_table_names;

    # from the database now
    my @current_table_names = $data_source->_get_table_names_from_data_dictionary();
    my %current_table_names = map { s/"|'//g; uc($_) => 1 } @current_table_names;

    my %all_table_names = (%current_table_names, %previous_table_names);

    my $new_object_revision = UR::Time->now();

    # handle tables which are new/updated by updating the class
    my (@create,@delete,@update);
    my $pattern = '%-42s';
    my ($dsn) = ($data_source =~ /^.*::DataSource::(.*?)$/);
    for my $table_name (keys %all_table_names) {
        my $last_actual_ddl_time = $last_ddl_time_for_table_name->{$table_name};

        my $table_object;
        my $last_recorded_ddl_time;
        my $last_object_revision;

        eval {
            #($table_object) = $data_source->get_tables(table_name => $table_name);

            # Using the above doesn't account for a table switching databases, which happens.
            # Once the data source is _part_ of the id we'll just have a delete/add, but for now it's an update.
            $table_object = UR::DataSource::RDBMS::Table->get(data_source => $data_source,
                                                              table_name => $table_name);
        };

        if ($current_table_names{$table_name} and not $table_object) {
            # new table
            push @create, $table_name;
            $self->status_message(
                sprintf(
                    "A  $pattern Schema changes " . ($last_actual_ddl_time ? "on $last_actual_ddl_time" : ""),
                    $dsn . " " . $table_name
                )
            );
            my $table_object = $self->_update_database_metadata_objects_for_table_changes($data_source,$table_name);
            next unless $table_object; 

            $table_object->last_ddl_time($last_ddl_time_for_table_name->{$table_name});
        }
        elsif ($current_table_names{$table_name} and $table_object) {
            # retained table
            # either we know it changed, or we can't know, so update it anyway
            if (! exists $last_ddl_time_for_table_name->{$table_name} or
                ! defined $table_object->last_ddl_time or
                $last_ddl_time_for_table_name->{$table_name} gt $table_object->last_ddl_time
            ) {
                my $last_update = $table_object->last_ddl_time || $table_object->last_object_revision;
                my $this_update = $last_ddl_time_for_table_name->{$table_name} || "<unknown date>";
                #$table_object->delete;
                my $table_object = $self->_update_database_metadata_objects_for_table_changes($data_source,$table_name);
                unless ($table_object) {
                    #$DB::single = 1;
                    print;
                }
                my @changes =
                    grep { not  ($_->properties == 1 and ($_->properties)[0] eq "last_object_revision") }
                    $table_object->changed;
                if (@changes) {
                    $self->status_message(
                        sprintf("U  $pattern Last updated on $last_update.  Newer schema changes on $this_update."
                            , $dsn . " " . $table_name
                        )
                    );                        
                    push @update, $table_name;
                }
                $table_object->last_ddl_time($last_ddl_time_for_table_name->{$table_name});
            }
        }
        elsif ($table_object and not $current_table_names{$table_name}) {
            # deleted table
            push @delete, $table_name;
            $self->status_message(
                sprintf(
                    "D  $pattern Last updated on %s.  Table dropped.",
                    $dsn . " " . $table_name,
                    $last_object_revision || "<unknown date>"
                )
            );
            my $table_object = UR::DataSource::RDBMS::Table->get(
                                       data_source => $data_source->class,
                                       table_name => $table_name,
                                   );
            $table_object->delete;
        }
        else {
            Carp::confess("Unable to categorize table $table_name as new/old/deleted?!");
        }
    }

    return 1;
}


# Keep a cache of class meta objects so we don't have to keep asking the 
# object system to do it for us.  This should be a speed optimization because
# the asking eventually filters down to calling get_material_classes() on the
# namespace which can be extremely slow.  If it's not in the cache, defer to 
# asking the data source
sub _get_class_meta_for_table_name {
    my($self,%param) = @_;

    my $data_source = $param{'data_source'};
    my $data_source_name = $data_source->get_name();
    my $table_name = $param{'table_name'};

    my ($obj) = 
        grep { not $_->isa("UR::Object::Ghost") } 
        UR::Object::Type->is_loaded(
            data_source => $data_source,
            table_name => $table_name
        );
    return $obj if $obj;


    unless ($self->{'_class_meta_cache'}{$data_source_name}) {
        my @classes =
            grep { not $_->class_name->isa('UR::Object::Ghost') } 
            UR::Object::Type->get(data_source => $data_source);
            
        for my $class (@classes) {
            my $table_name = $class->table_name;
            next unless $table_name;
            $self->{'_class_meta_cache'}->{$data_source_name}->{$table_name} = $class;
        }        
    }
    
    $obj = $self->{'_class_meta_cache'}->{$data_source_name}->{$table_name};
    return $obj if $obj;
    return;
}


sub  _update_class_metadata_objects_to_match_database_metadata_changes {
    my ($self, %params) = @_;

    my $data_dictionary_objects = delete $params{data_dictionary_objects};
    if (%params) {
        $self->error_message("Unknown params!");
        return;
    }

    #
    # INITIALIZATION AND SANITY CHECKING
    #

    my $namespace = $self->namespace_name;

=cut

    $self->status_message("Using filesystem classes for namespace \"$namespace\" (this may be slow)");
    my @material_classes = $namespace->get_material_classes;


    $self->status_message("Verifying class/table relationships...");
    my %table_ids_used;
    for my $class (sort { $a->class_name cmp $b->class_name } @material_classes) {
        my $table_name  = $class->table_name;
        next unless $table_name;

        my $class_name  = $class->class_name;

        if (my $prev_class_name = $table_ids_used{$table_name}) {
            $self->error_message(
                sprintf(
                    "C %-40s uses table %-32s, but so does %-40s" . "\n",
                    $class_name, $table_name, $prev_class_name
                )
            );
            return;
        }

        my $data_source = $class->data_source;

        my $table = UR::DataSource::RDBMS::Table->get(data_source => $data_source, table_name => $table_name)
                    ||
                    UR::DataSource::RDBMS::Table::Ghost->get(data_source => $data_source, table_name => $table_name);

        unless ($table) {
            $self->error_message(
                sprintf(
                    "C %-32s %-32s is referenced by class %-40s but cannot be found!?" . "\n",
                    $data_source, $table_name, $class_name
                )
            );
            return;
        }
        $table_ids_used{$table_name} = $class;
    }

=cut

    $self->status_message("Updating classes...");

    my %dd_changes_by_class = (
        'UR::DataSource::RDBMS::Table' => [],
        'UR::DataSource::RDBMS::TableColumn' => [],
        'UR::DataSource::RDBMS::FkConstraint' => [],
        'UR::DataSource::RDBMS::Table::Ghost' => [],
        'UR::DataSource::RDBMS::TableColumn::Ghost' => [],
        'UR::DataSource::RDBMS::FkConstraint::Ghost' => [],
    );
    for my $changed_obj (@$data_dictionary_objects) {
        my $changed_class = $changed_obj->class;
        my $bucket = $dd_changes_by_class{$changed_class};
        push @$bucket, $changed_obj;
    }
    my $sorter = sub { $a->table_name cmp $b->table_name || $a->id cmp $b->id };

    # FKs are special, in that they might change names, but we use the name as the "id".
    # This should change, really, but until it does we need to identify them by their "content",

    #
    # DELETIONS
    #

    # DELETED FK CONSTRAINTS
    #  Just detach the object reference meta-data from the constraint.
    #  We only actually delete references when their properties all go away,
    #  which can happen when the columns go away (through table deletion or alteration).
    #  It can also happen when one of the involved classes is deleted, which never happens
    #  automatically.
    
    for my $fk (sort $sorter @{ $dd_changes_by_class{'UR::DataSource::RDBMS::FkConstraint::Ghost'} }) {
        my $table = $fk->get_table;
        # FIXME should this use $data_source->get_class_meta_for_table($table) instead?
        my $class = 
            UR::Object::Type->get(
                data_source => $table->data_source,
                table_name => $table->table_name,
            )
            ||
            UR::Object::Type::Ghost->get(
                data_source => $table->data_source,
                table_name => $table->table_name,
            );

        unless ($class) {
            #$DB::single = 1;
            $self->status_message(sprintf("~ No class found for deleted foreign key constraint %-32s %-32s" . "\n",$table->table_name, $fk->id));
            next;
        }
        my $class_name = $class->class_name;
        my $reference = UR::Object::Reference->get(
            class_name => $class_name,
            constraint_name => $fk->fk_constraint_name, # switch to constraint "id"
        );
        unless ($reference) {
            # FIXME should we do a $fk->delete() here?
            #$DB::single = 1;
            $self->status_message(sprintf("~ No reference found for deleted foreign key constraint %-32s %-32s" . "\n",$table->table_name, $fk->id));
            next;
        }
        $reference->constraint_name(undef);
    }

    # DELETED UNIQUE CONSTRAINTS
    # DELETED PK CONSTRAINTS
    #  We do nothing here, because we don't track these as individual DD objects, just values on the table object.
    #  If a table changes constraints, that is handled below after table/column add/update.
    #  If a table is dropped entirely, we leave all pk/unique constraints in place,
    #  since, if the class is not manually deleted by the developer, it should continue
    #  to function as it did before.

    # DELETED COLUMNS
    for my $column (sort $sorter @{ $dd_changes_by_class{"UR::DataSource::RDBMS::TableColumn::Ghost"} }) {
        my $table = $column->get_table;
        my $column_name = $column->column_name;

        # FIXME should this use $data_source->get_class_meta_for_table($table) instead?
        my $class = UR::Object::Type->get(
            data_source => $table->data_source,
            table_name => $table->table_name,
        );
        unless ($class) {
            $self->status_message(sprintf("~ No class found for deleted column %-32s %-32s\n", $table->table_name, $column_name));
            next;
        }
        my $class_name = $class->class_name;

        my ($property) = $class->get_property_objects(
            column_name => $column_name
        );
        unless ($property) {
            $self->status_message(sprintf("~ No property found for deleted column %-32s %-32s\n",$table->table_name, $column_name));
            next;
        }

        my @reference_property_from = UR::Object::Reference::Property->get(
            class_name => $class_name,
            property_name => $property->property_name,
        );
        my @reference_property_to = UR::Object::Reference::Property->get(
            r_class_name => $class_name,
            r_property_name => $property->property_name,
        );
        my @reference_ids = map { $_->reference_id } (@reference_property_from, @reference_property_to);
        for my $reference_property (@reference_property_from, @reference_property_to) {
            $reference_property->delete;
        }
        for my $reference_id (@reference_ids) {
            my $reference = UR::Object::Reference->get($reference_id);
            next unless $reference;
            if (my @other_property_links = $reference->get_property_links()) {
                for my $other_property_link (@other_property_links) {
                    $other_property_link->delete;
                }
            }
            $reference->delete;
        }

        unless ($table->isa("UR::DataSource::RDBMS::Table::Ghost")) {
            $self->status_message(
                sprintf(
                    "D %-32s deleted from class %-40s for deleted column %-32s" . "\n",
                    $property->property_name,
                    $class->class_name,
                    $column->column_name
                )
            );
        }

        $property->delete;

        unless ($property->isa("UR::DeletedRef")) {
            Carp::confess("Error deleting property " . $property->id);
        }
    }

    # DELETED TABLES
    my %classes_with_deleted_tables;
    for my $table (sort $sorter @{ $dd_changes_by_class{"UR::DataSource::RDBMS::Table::Ghost"} }) {
        # Though we create classes for tables, we don't immediately delete them, just deflate them.
        my $table_name = $table->table_name;
        if (not defined UR::Context->_get_committed_property_value($table,'table_name')) {
            print Data::Dumper::Dumper($table);
            #$DB::single = 1;
        }
        # FIXME should this use $data_source->get_class_meta_for_table($table) instead?
        my $class = UR::Object::Type->get(
            data_source => UR::Context->_get_committed_property_value($table,'data_source'),
            table_name => UR::Context->_get_committed_property_value($table,'table_name'),
        );
        unless ($class) {
            $self->status_message(sprintf("~ No class found for deleted table %-32s" . "\n",$table_name));
            next;
        }
        $classes_with_deleted_tables{$table_name} = $class;
        $class->data_source(undef);
        $class->table_name(undef);
    } # next deleted table

    for my $table_name (keys %classes_with_deleted_tables) {
        my $class = $classes_with_deleted_tables{$table_name};
        my $class_name = $class->class_name;

        my %ancestory = map { $_ => 1 } $class->inheritance;
        my @ancestors_with_tables =
            grep {
                $a = UR::Object::Type->get(class_name => $_)
                    || UR::Object::Type::Ghost->get(class_name => $_);
                $a && $a->table_name;
            } sort keys %ancestory;
        if (@ancestors_with_tables) {
            $self->status_message(
                sprintf("U %-40s is now detached from deleted table %-32s.  It still inherits from classes with persistent storage." . "\n",$class_name,$table_name)
            );
        }
        else {
            my @parent_class_links = UR::Object::Inheritance->get(class_name => $class->class_name);
            for my $parent_class_link (@parent_class_links) {
                $parent_class_link->delete;
            }
            my @id_property_links = UR::Object::Property::ID->get(class_name => $class->class_name);
            for my $id_property_link (@id_property_links) {
                $id_property_link->delete;
            }
            $class->delete;
            #$DB::single = 1;
            $self->status_message(
                #sprintf("D %-40s deleted for deleted table %-32s" . "\n",$class_name,$table_name)
                sprintf("D %-40s deleted for deleted table %s" . "\n",$class_name,$table_name)
            );
        }
    } # next deleted table

    # This is the data structure used by _get_class_meta_for_table_name
    # There's a bad interaction with software transactions that can lead
    # to this cache containing deleted class objects if the caller holds
    # on to a reference to this command object and repetedly calls execute()
    # but rolls back transactions between those calls.
    $self->{'_class_meta_cache'} = {};

    #$DB::single = 1;

    #
    # EXISTING DD OBJECTS
    #
    # TABLE
    for my $table (sort $sorter @{ $dd_changes_by_class{"UR::DataSource::RDBMS::Table"} }) {
        my $table_name = uc $table->table_name;
        my $data_source = $table->data_source;

        #my $class = grep { not $_->isa('UR::Object::Ghost') }
        #                UR::Object::Type->get(
        #                       namespace => $namespace,
        #                       #data_source => $data_source,
        #                       table_name => $table_name,
        #                 );
        #my $class =  UR::Object::Type->get(
        #                       namespace => $namespace,
        #                       #data_source => $data_source,
        #                       table_name => $table_name,
        #                 );
        #my $class = $data_source->get_class_meta_for_table_name($table_name);
        my $class = $self->_get_class_meta_for_table_name(data_source => $data_source,
                                                          table_name => $table_name);
      
        if ($class) {
            # update

            if ($class->data_source ne $table->data_source) {
                $class->data_source($table->data_source);
            }

            my $class_name = $class->class_name;
            no warnings;
            if ($table->remarks ne UR::Context->_get_committed_property_value($table,'remarks')) {
                $class->doc($table->remarks);
            }
            if ($table->data_source ne UR::Context->_get_committed_property_value($table,'data_source')) {
                $class->data_source($table->data_source);
            }
            
            if ($class->changed) {
                $self->status_message(
                    #sprintf("U %-40s uses table %-40s" . "\n",$class_name,$table_name)
                    sprintf("U %-40s uses %s %s %s" . "\n",$class_name,
                                                           $table->data_source->get_name,
                                                           lc($table->table_type),
                                                           $table_name)
                );
            }
        }
        else {
            # create
            my $data_source = $table->data_source;
            my $class_name = $data_source->resolve_class_name_for_table_name($table_name,$table->table_type);
            unless ($class_name) {
                Carp::confess(
                        "Failed to resolve a class name for new table "
                        . $table_name
                );
            }

            # if the original table_name was empty (ie. not backed by a table), and the
            # new one actually has a table, then this is just another schema change and
            # not an error.  Set the table_name attribute and go on...
            my $class = UR::Object::Type->get(class_name => $class_name);
            my $prev_table_name = $class->table_name if ($class);
            if ($class && $prev_table_name) {

                Carp::confess(
                    "Class $class_name already exists for table '$prev_table_name'."
                    . "  Cannot generate class for $table_name."
                );
            }

            $self->status_message(
                     #sprintf("A %-40s uses table %-40s" . "\n",$class_name,$table_name)
                     sprintf("A %-40s uses %s %s %s" . "\n",$class_name,
                                                            $table->data_source->get_name,
                                                            lc($table->table_type),
                                                            $table_name)
                  );

            my $type_name = $data_source->resolve_type_name_for_table_name($table_name);
            $type_name .= ' view' if ($table->table_type =~ m/view/i);
            unless ($type_name) {
                Carp::confess(
                    "Failed to resolve a type name for new table "
                    . $table_name
                );
            }

            if ($class) {
                $class->type_name($type_name);
                $class->doc($table->remarks ? $table->remarks: undef);
                $class->data_source($data_source);
                $class->table_name($table_name);
                # FIXME we should pick one of these names to standarize on
                $class->er_role($table->er_type);
            } else {
                $class = UR::Object::Type->create(
                            class_name => $class_name,
                            type_name => $type_name,
                            doc => ($table->remarks ? $table->remarks: undef),
                            data_source => $data_source,
                            table_name => $table_name,
                            er_role => $table->er_type,
                            # generate => 0,
                );                
                unless ($class) {
                    Carp::confess(
                        "Failed to create class $class_name for new table "
                        . $table_name
                        . ". " . UR::Object::Type->error_message
                    );
                }
            }

            unless ($class->class_name->isa('UR::Entity')) {
                my $inheritance = UR::Object::Inheritance->create(
                    type_name => $class->type_name,
                    class_name => $class->class_name,
                    parent_class_name => "UR::Entity",
                    parent_type_name => "table row",
                    inheritance_priority => 0,
                );
                Carp::confess("Failed to generate inheritance link!?") unless $inheritance;
            }
        }
    } # next table

    $self->status_message("Updating class properties...\n");
    # COLUMN
    my @column_property_translations = (
        ['data_type'    => 'data_type'],
        ['data_length'  => 'data_length'],
        ['nullable'     => 'is_optional', sub { (defined($_[0]) and ($_[0] eq "Y")) ? 1 : 0 } ],
        ['remarks'      => 'doc'],
    );
    
    for my $column (sort $sorter @{ $dd_changes_by_class{'UR::DataSource::RDBMS::TableColumn'} }) {
        my $table = $column->get_table;
        my $column_name = $column->column_name;
        my $data_source = $table->data_source;

        #my $class = UR::Object::Type->get(
        #    data_source => $table->data_source,
        #    table_name => $table->table_name,
        #);
        #my $class = $data_source->get_class_meta_for_table($table);
        my $class = $self->_get_class_meta_for_table_name(data_source => $data_source,
                                                          table_name => $table->table_name);

        unless ($class) {
            #$DB::single = 1;
            $class = $self->_get_class_meta_for_table_name(data_source => $data_source,
                                                          table_name => $table->table_name);
            Carp::confess("Class object missing for table " . $table->table_name) unless $class;
        }
        my $class_name = $class->class_name;
        my $property;
        $column_name = uc($column_name);
        foreach my $prop_object ( $class->get_property_objects ) {
            if (uc($prop_object->column_name) eq $column_name) {
                $property = $prop_object;
                last;
            }
       }

        # We care less whether the column is new/updated, than whether there is property metadata for it.
        if ($property) {
            # update
            for my $translation (@column_property_translations) {
                my ($column_attr, $property_attr, $conversion_sub) = @$translation;
                $property_attr ||= $column_attr;

                no warnings;
                if (UR::Context->_get_committed_property_value($column,$column_attr) ne $column->$column_attr) {
                    if ($conversion_sub) {
                        $property->$property_attr($conversion_sub->($column->$column_attr));
                    }
                    else {
                        $property->$property_attr($column->$column_attr);
                    }
                }
            }
            $property->data_type($column->data_type);
            $property->data_length($column->data_length);
            $property->is_optional($column->nullable eq "Y" ? 1 : 0);
            $property->doc($column->remarks);
            
            if ($property->changed) {
                no warnings;
                $self->status_message(
                    #sprintf("U %-40s uses table %-40s" . "\n",$class_name,$table_name)
                    sprintf("U %-40s has updated column %s.%s (%s %s)" . "\n",                                                         
                                                            $class_name,
                                                            $table->table_name, 
                                                            $column_name,
                                                            $column->data_type,
                                                            $column->data_length)
                );
            }
        }
        else {
            # create
            my $property_name = $data_source->resolve_property_name_for_column_name($column->column_name);
            unless ($property_name) {
                Carp::confess(
                        "Failed to resolve a property name for new column "
                        . $column->column_name
                );
            }

            my $attribute_name = $data_source->resolve_attribute_name_for_column_name($column->column_name);
            unless ($attribute_name) {
                Carp::confess(
                    "Failed to resolve a attribute name for new column "
                    . $column->column_name
                );
            }

            my $type_name = $class->type_name;

            $property = UR::Object::Property->create(
                class_name     => $class_name,
                type_name      => $type_name,
                attribute_name => $attribute_name,
                property_name  => $property_name,
                column_name    => $column_name,
                data_type      => $column->data_type,
                data_length    => $column->data_length,
                is_optional    => $column->nullable eq "Y" ? 1 : 0,
                is_volatile    => 0,
                doc            => $column->remarks,
                is_specified_in_module_header => 1, 
            );
            
            no warnings;
            $self->status_message(
                sprintf("A %-40s has new column %s.%s (%s %s)" . "\n",                                                         
                                                        $class_name,
                                                        $table->table_name, 
                                                        $column_name,
                                                        $column->data_type,
                                                        $column->data_length)
            );
            
            unless ($property) {
                Carp::confess(
                        "Failed to create property $property_name on class $class_name. "
                        . UR::Object::Property->error_message
                );
            }
        }
        
        # FIXME Moved the creating/setting of these properties up a bit, since the
        # create() invovles a call into the class object containing the property, which handles
        # updating the class' flat-format data.  Changing the 
        #$property->data_type($column->data_type);
        #$property->data_length($column->data_length);
        #$property->is_optional($column->nullable eq "Y" ? 1 : 0);
        #$property->doc($column->remarks);

    } # next column

    $self->status_message("Updating class relationships...\n");

    # PK CONSTRAINTS (loop table objects again, since the DD doesn't do individual ID objects)
    for my $table (sort $sorter @{ $dd_changes_by_class{'UR::DataSource::RDBMS::Table'} }) {
        # created/updated/unchanged
        # delete and re-create these objects: they're "bridges", so no developer supplied data is presesent
        my $table_name = $table->table_name;

        #my $class = UR::Object::Type->get(
        #    data_source => $table->data_source,
        #    table_name => $table->table_name,
        #);
        #my $class = $table->get_class_meta();
        my $class = $self->_get_class_meta_for_table_name(data_source => $table->data_source,
                                                          table_name => $table_name);
        my $class_name = $class->class_name;
        my $type_name = $class->type_name;
        my @properties = UR::Object::Property->get(class_name => $class_name);

        unless (@properties) {
            $self->warning_message("no properties on class $class_name?");
            #$DB::single = 1;
        }

        my @id_properties =
            UR::Object::Property::ID->get(
                class_name=> $class_name
            );
        
        my @expected_pk_cols = map { $class->get_property_meta_by_name($_->property_name)->column_name } @id_properties;
        
        my @pk_cols = $table->primary_key_constraint_column_names;
        
        if ("@expected_pk_cols" eq "@pk_cols") {
            next;
        }
        
        for my $property (@id_properties) { $property->delete };        
        
        unless (@pk_cols) {
            # If there are no primary keys defined, then treat _all_ the columns
            # as primary keys.  This means we don't support multiple rows in a
            # table containing the same data.
            @pk_cols = $table->column_names;
        }
        for my $pos (1 .. @pk_cols)
        {
            my $pk_col = $pk_cols[$pos-1];
            my ($property) = grep { defined($_->column_name) and (uc($_->column_name) eq uc($pk_col)) } @properties;
            
            unless ($property) {
                # the column has been removed
                next;
            }
            
            my $property_name = $property->property_name;
            my $attribute_name = $property->attribute_name;
            unless ($attribute_name) {
                $self->error_message(
                    "Failed to find attribute name for table $table_name column $pk_col!"
                    . UR::Object::Property::Unique->error_message
                );
            }

            my $id_property = UR::Object::Property::ID->create(
                class_name => $class_name,
                type_name => $type_name,
                property_name => $property_name,
                attribute_name => $attribute_name,
                position => $pos
            );
            unless ($id_property) {
                $self->error_message(
                    "Failed to create identity specification for $class_name/$property_name ($pos)!"
                    . UR::Object::Property::Unique->error_message
                );
            }
        }
    } # next table (looking just for PK constraint changes)

    $self->status_message("Updating class unique constraints...\n");

    #$DB::single = 1;

    # UNIQUE CONSTRAINT / UNIQUE INDEX -> UNIQUE GROUP (loop table objecs since we have no PK DD objects)
    for my $table (sort $sorter @{ $dd_changes_by_class{'UR::DataSource::RDBMS::Table'} }) {
        # created/updated/unchanged
        # delete and re-create

        #my $class = UR::Object::Type->get(
        #    data_source => $table->data_source,
        #    table_name => $table->table_name,
        #);
        #my $class = $table->get_class_meta();
        my $class = $self->_get_class_meta_for_table_name(data_source => $table->data_source,
                                                          table_name => $table->table_name);
        my $class_name = $class->class_name;
        my $type_name = $class->type_name;

        my @properties = UR::Object::Property->get(class_name => $class_name);

        my @prev_unique_constraints =
            UR::Object::Property::Unique->get(
                class_name => $class_name
            );

        for my $constraint (@prev_unique_constraints) {
            $constraint->delete;
        }

        my @uc_names = $table->unique_constraint_names;
        for my $uc_name (@uc_names)
        {
            my @uc_cols = map { ref($_) ? @$_ : $_ } $table->unique_constraint_column_names($uc_name);
            for my $uc_col (@uc_cols)
            {
                my ($property) = grep { defined($_->column_name) and ($_->column_name eq $uc_col) } @properties;
                unless ($property) {
                    $self->warning_message("No property found for column $uc_col for unique constraint $uc_name");
                    $DB::single=1;
                    next;
                }

                my $property_name = $property->property_name;
                my $attribute_name = $property->attribute_name;
                my $uc = UR::Object::Property::Unique->create(
                    class_name => $class_name,
                    type_name => $type_name,
                    property_name => $property_name,
                    attribute_name => $attribute_name,
                    unique_group => $uc_name
                );
                unless ($uc) {
                    Carp::confess(
                        "Error creating unique constraint $uc_name for class $class_name: "
                        . UR::Object::Property::Unique->error_message
                    );
                }
            }
        }
    } # next table (checking separately for unique constraints)


    # FK CONSTRAINTS
    #  These often change name, and as such need to be identified by their actual content.
    #  Each constraint must match some relationship in the system, or a new one will be added.

    $self->status_message("Updating class relationship constraints...\n");

    my %existing_references;
    my $last_class_name = '';
    FK:
    for my $fk (sort $sorter @{ $dd_changes_by_class{'UR::DataSource::RDBMS::FkConstraint'} }) {

        my $table = $fk->get_table;
        my $data_source = $fk->data_source;

        my $table_name = $fk->table_name;
        my $r_table_name = $fk->r_table_name;

        my $class = $self->_get_class_meta_for_table_name(data_source => $data_source,
                                                          table_name => $table_name);
        unless ($class) {
            Carp::confess(
                  sprintf("No class found for table for foreign key constraint %-32s %s" . "\n",$table_name, $fk->id)
               );
        }

        my $r_class = $self->_get_class_meta_for_table_name(data_source => $data_source,
                                                            table_name => $r_table_name);
        unless ($r_class) {
            Carp::confess(
                  sprintf("No class found for r_table for foreign key constraint %-32s %-32s" . "\n",$r_table_name, $fk->id)
               );
        }

        my $class_name = $class->class_name;
        my $r_class_name = $r_class->class_name;

        my $type_name = $class->type_name;
        my $r_type_name = $r_class->type_name;

        # Don't bother rebuilding this cache unless this FK's related class is different
        # than the one in the last pass through this loop.  Because of the way they get
        # sorted, it's likely that related FKs will be processed after each other
        if ($last_class_name ne $class_name) {
            %existing_references = map { ($self->_reference_fingerprint($_), $_) }
                                   UR::Object::Reference->get(class_name => $class_name);
            $last_class_name = $class_name;
        }

        #my $reference = $existing_references{$self->_foreign_key_fingerprint($fk)};
        my $fingerprint = $self->_foreign_key_fingerprint($fk);
        my $reference;
        $reference = $existing_references{$fingerprint};
        if ($reference) {
            $reference->constraint_name($fk->fk_constraint_name);
        } else {

            # Create a new reference object, and all the related Reference::Property objects
            my @column_names = $fk->column_names;
            my @r_column_names = $fk->r_column_names;
            my (@properties,@property_names,@r_properties,@r_property_names,$prefix,$suffix,$matched);
            foreach my $i ( 0 .. $#column_names ) {
                my $column_name = $column_names[$i];
                my $property = UR::Object::Property->get(
                                      class_name => $class_name,
                                      column_name => $column_name, 
                                );
                unless ($property) {
                    #$DB::single = 1;
                    Carp::confess("Failed to find a property for column $column_name on class $class_name");
                }
                push @properties,$property;
                my $property_name = $property->property_name;
                push @property_names,$property_name;
    
                my $r_column_name = $r_column_names[$i];
                my $r_property = UR::Object::Property->get(
                                      class_name => $r_class_name,
                                      column_name => $r_column_name,
                                );
                unless ($r_property) {
                    Carp::cluck("Failed to find a property for column $r_column_name on class $r_class_name");
                    $DB::single = 1;
                    next FK;
                }
                push @r_properties,$r_property;
                my $r_property_name = $r_property->property_name;
                push @r_property_names,$r_property_name;

                if ($property_name =~ /^(.*)$r_property_name(.*)$/
                    or $property_name =~ /^(.*)_id$/) {
    
                    $prefix = $1;
                    $prefix =~ s/_$//g if defined $prefix;
                    $suffix = $2;
                    $suffix =~ s/^_//g if defined $suffix;
                    $matched = 1;
                }
            }

            my $delegation_name = $r_class->type_name;
            $delegation_name =~ s/ /_/g;
            if ($matched) {
                $delegation_name = $delegation_name . "_" . $prefix if $prefix;
                $delegation_name .= ($suffix !~ /\D/ ? "" : "_") . $suffix if $suffix;
            }
            else {
                $delegation_name = join("_", @property_names) . "_" . $delegation_name;
            }
    
            # Generate a delegation name that dosen't conflict with another already in use
            my %delegation_names_used = map { $_->delegation_name => 1 }
                                            UR::Object::Reference->get(class_name => $class_name);
            while($delegation_names_used{$delegation_name}) {
                $delegation_name =~ /^(.*?)(\d*)$/;
                $delegation_name = $1 . ( ($2 ? $2 : 0) + 1 );
            }
                
            my $reference_id = $class_name . "::" . $delegation_name;
            $reference = UR::Object::Reference->create(
                                 tha_id => $reference_id,
                                 class_name => $class_name,
                                 r_class_name => $r_class_name,
                                 type_name => $type_name,
                                 r_type_name => $r_type_name,
                                 delegation_name => $delegation_name,
                                 constraint_name => $fk->fk_constraint_name,
                            );
            unless ($reference) {
                #$DB::single = 1;
                Carp::confess("Failed to create a new reference object for tha_id $reference_id");
            }

            # FK columns may have been in an odd order.  Get the reference columns in ID order.            

            for my $i (0..$#column_names)
            {
                my $column_name = $column_names[$i];
                #my $property = UR::Object::Property->get(
                #    class_name => $class_name,
                #    column_name => $column_name
                #);
                my $property = $properties[$i];
                my $attribute_name = $property->attribute_name;
                my $property_name = $property_names[$i];

                my $r_column_name = $r_column_names[$i];
                #my $r_property = UR::Object::Property->get(
                #    class_name => $r_class_name,
                #    column_name => $r_column_name
                #);
                my $r_property = $r_properties[$i];
                my $r_attribute_name = $r_property->attribute_name;
                my $r_property_name = $r_property_names[$i];

                my $id_meta = UR::Object::Property::ID->get(
                    class_name => $r_class_name,
                    property_name => $r_property_name,
                );

                my $reference_property = UR::Object::Reference::Property->create(
                    tha_id => $reference_id,
                    rank => $id_meta->position,
                    attribute_name => $attribute_name,
                    property_name => $property_name,
                    r_attribute_name => $r_attribute_name,
                    r_property_name => $r_property_name
                );
                unless ($reference_property) {
                    Carp::confess("Failed to create a new reference property for tha_id $reference_id property_name $property_name r_property_name $r_property_name");
                }
            }
        } # end create a new reference object

    } # next fk constraint

    return 1;
}


# For an UR::Object::Reference, return a thingy that can be directly compared
# to a fingerprint from a UR::DataSource::RDBMS::FkConstraint.  It contains
# info from the class and table's columns involved, but not the FK name
# Maybe this should be moved to UR::Object::Reference...
sub _reference_fingerprint {
my($self,$reference) = @_;

    my $class_name = $reference->class_name;
    my @columns =
          sort
          map { $_->column_name }
          map { UR::Object::Property->get(class_name => $class_name, property_name => $_) }
          $reference->property_link_names();

    my $r_class_name = $reference->r_class_name;
    my @r_columns = 
          sort
          map { $_->column_name }
          map { UR::Object::Property->get(class_name => $r_class_name, property_name => $_) }
          $reference->r_property_link_names();

    return $class_name . ':' . join(',',@columns) . ':' . join(',',@r_columns);
}

sub _foreign_key_fingerprint {
my($self,$fk) = @_;

    my $class = $self->_get_class_meta_for_table_name(data_source => $fk->data_source,
                                                      table_name => $fk->table_name);

    return $class->class_name . ':' . join(',',sort $fk->column_names) . ':' . join(',',sort $fk->r_column_names);
}




sub _sync_filesystem {
    my $self = shift;
    my %params = @_;

    my $changed_class_names = delete $params{changed_class_names};
    if (%params) {
        Carp::confess("Invalid params passed to _sync_filesystem: " . join(",", keys %params) . "\n");
    }

    my $obsolete_module_directory = $self->namespace_name->get_deleted_module_directory_name;

    my $namespace = $self->namespace_name;
    my $no_commit = UR::DBI->no_commit;
    $no_commit = 0 if $self->{'_override_no_commit_for_filesystem_items'};

    for my $class_name (@$changed_class_names) {        
        my $status_message_this_update = '';
        my $class_obj;
        my $prev;
        if ($class_obj = UR::Object::Type->get(class_name => $class_name)) {
            if ($class_obj->{is}[0] =~ /::Type$/ and $class_obj->{is}[0]->isa('UR::Object::Type')) {
                next;
            }
            if ($class_obj->db_committed) {
                $status_message_this_update .= "U " . $class_obj->class_name;
            }
            else {
                $status_message_this_update .= "A " . $class_obj->class_name;
            }
            $class_obj->rewrite_module_header() unless ($no_commit);
            # FIXME A test of automaticly making DBIx::Class modules
            #$class_obj->dbic_rewrite_module_header() unless ($no_commit);

        }
        elsif ($class_obj = UR::Object::Type::Ghost->get(class_name => $class_name)) {
            if ($class_obj->{is}[0] eq 'UR::Object::Type') {
                next;
            }
            
            $status_message_this_update = "D " . $class_obj->class_name;
            
            unless ($no_commit) {
                unless (-d $obsolete_module_directory) {
                    mkdir $obsolete_module_directory;
                    unless (-d $obsolete_module_directory) {
                        $self->error_message("Unable to create $obsolete_module_directory for the deleted module for $class_name.");
                        next;
                    }
                }

                my $f = IO::File->new($class_obj->module_path);
                my $old_file_data = join('',$f->getlines);
                $f->close();

                my $old_module_path = $class_obj->module_path;
                my $new_module_path = $old_module_path;
                $new_module_path =~ s/\/$namespace\//\/$namespace\/\.deleted\//;
                $status_message_this_update .= ' (moving $old_module_path $new_module_path)';
                rename $old_module_path, $new_module_path;

                UR::Context::Transaction->log_change($class_obj, $class_obj->class_name, $class_obj->id, 'rewrite_module_header', Data::Dumper::Dumper({path => $new_module_path, data => $old_file_data}));
            }
        }
        else {
            Carp::confess("Failed to find regular or ghost class meta-object for class $class_name!?");
        }
       
        if ($no_commit) {
            $status_message_this_update .= ' (ignored - no-commit)';
        }
        $self->status_message($status_message_this_update);

    }

    return 1;
}

#
# The following two methods do the real work on a per-table basis.
# They'll possibly be moved into an action for the table object?
#


sub _update_database_metadata_objects_for_table_changes {
    my ($self,$data_source,$table_name) = @_;

    my @column_objects;
    my @all_constraints;

    # this must be on or before the actual data dictionary queries
    my $revision_time = UR::Time->now();

    # TABLE
    my $table_sth = $data_source->get_table_details_from_data_dictionary('%', $data_source->owner, $table_name, "TABLE,VIEW");
    my $table_data = $table_sth->fetchrow_hashref();
    unless ($table_data && %$table_data) {
        #Carp::confess("No data for table $table_name in data source $data_source?!");
        Carp::cluck("No data for table $table_name in data source $data_source?!");
        return undef;
    }

    my $table_object = UR::DataSource::RDBMS::Table->get(data_source => $data_source,
                                                         table_name => $table_name);
    if ($table_object) {
        # Already exists, update the existing entry
        # Instead of deleting and recreating the table object (the old way),
        # modify its attributes in-place.  The name can't change but all the other
        # stuff might.
        $table_object->table_type($table_data->{TABLE_TYPE});
        $table_object->owner($table_data->{TABLE_SCHEM});
        $table_object->data_source($data_source->class);
        $table_object->remarks($table_data->{REMARKS});
        $table_object->last_object_revision($revision_time) if ($table_object->changed());

    } else {
        # Create a brand new one from scratch

        $table_object = UR::DataSource::RDBMS::Table->create(
            table_name => $table_name,
            table_type => $table_data->{TABLE_TYPE},
            owner => $table_data->{TABLE_SCHEM},
            data_source => $data_source->class,
            remarks => $table_data->{REMARKS},
            last_object_revision => $revision_time,
        );
        unless ($table_object) {
            Carp::confess("Failed to get/create table object for $table_name");
        }
    }


    # COLUMNS
    # mysql databases seem to require you to actually put in the database name in the first arg
    my $db_name = ($data_source->can('db_name')) ? $data_source->db_name : '%';
    my $column_sth = $data_source->get_column_details_from_data_dictionary($db_name, $data_source->owner, $table_name, '%');
    unless ($column_sth) {
        $self->error_message("Error getting column data for table $table_name in data source $data_source.");
        return;
    }
    my $all_column_data = $column_sth->fetchall_arrayref({});
    unless (@$all_column_data) {
        $self->error_message("No column data for table $table_name in data source $data_source");
        return;
    }
    
    my %columns_to_delete = map {$_->column_name, $_} UR::DataSource::RDBMS::TableColumn->get(table_name => $table_name,
                                                                                              data_source => $data_source);
    
    
    
    for my $column_data (@$all_column_data) {

        #my $id = $table_name . '.' . $column_data->{COLUMN_NAME}
        $column_data->{'COLUMN_NAME'} =~ s/"|'//g;  # Postgres puts quotes around things that look like keywords
        $column_data->{'COLUMN_NAME'} = uc($column_data->{'COLUMN_NAME'});
        
        delete $columns_to_delete{$column_data->{'COLUMN_NAME'}};
        
        my $column_obj = UR::DataSource::RDBMS::TableColumn->get(table_name => $table_name,
                                                                 data_source => $data_source,
                                                                 column_name => $column_data->{'COLUMN_NAME'});
        if ($column_obj) {
            # Already exists, change the attributes
            $column_obj->owner($table_object->{owner});
            $column_obj->data_source($table_object->{data_source});
            $column_obj->data_type($column_data->{TYPE_NAME});
            $column_obj->nullable(substr($column_data->{IS_NULLABLE}, 0, 1));
            $column_obj->data_length($column_data->{COLUMN_SIZE});
            $column_obj->remarks($column_data->{REMARKS});
            $column_obj->last_object_revision($revision_time) if ($column_obj->changed());

        } else {
            # It's new, create it from scratch
            
            $column_obj = UR::DataSource::RDBMS::TableColumn->create(
                column_name => $column_data->{COLUMN_NAME},
                table_name  => $table_object->{table_name},
                owner       => $table_object->{owner},
                data_source => $table_object->{data_source},
        
                data_type   => $column_data->{TYPE_NAME},
                nullable    => substr($column_data->{IS_NULLABLE}, 0, 1),
                data_length => $column_data->{COLUMN_SIZE},
                remarks     => $column_data->{REMARKS},
                last_object_revision => $revision_time,
            );
        }

        unless ($column_obj) {
            Carp::confess("Failed to create a column ".$column_data->{'COLUMN_NAME'}." for table $table_name");
        }

        push @column_objects, $column_obj;
    }
    
    for my $to_delete (values %columns_to_delete) {
        $self->status_message("Detected column " . $to_delete->column_name . " has gone away.");
        $to_delete->delete;
    }


    my $bitmap_data = $data_source->get_bitmap_index_details_from_data_dictionary($table_name);
    for my $index (@$bitmap_data) {
        #push @{ $embed{bitmap_index_names}{$table_object} }, $index->{'index_name'};

        my $column_object = UR::DataSource::RDBMS::TableColumn->is_loaded(
            table_name => uc($index->{'table_name'}),
            data_source => $data_source,
            column_name => uc($index->{'column_name'}),
        );
    }


    # get foreign_key_info one way
    # constraints on other tables against columns in this table

    my $db_owner = $data_source->owner;
    my $fk_sth = $data_source->get_foreign_key_details_from_data_dictionary('', $db_owner, $table_name, '', '', '');

    my %fk;     # hold the fk constraints that this
                # invocation of foreign_key_info created

    my @constraints;

    if ($fk_sth) {
        while (my $data = $fk_sth->fetchrow_hashref()) {
            #push @$ref_fks, [@$data{qw(FK_NAME FK_TABLE_NAME)}];
    
            foreach ( qw( FK_TABLE_NAME UK_TABLE_NAME FK_NAME FK_COLUMN_NAME UK_COLUMN_NAME ) ) {
                $data->{$_} = uc($data->{$_});
            }

            my $fk = UR::DataSource::RDBMS::FkConstraint->get(table_name => $data->{'FK_TABLE_NAME'},
                                                              data_source => $data_source,
                                                              fk_constraint_name => $data->{'FK_NAME'},
                                                              r_table_name => $data->{'UK_TABLE_NAME'},
                                                             );
    
            unless ($fk) {
                # Postgres puts quotes around things that look like keywords
                foreach ( $data->{'FK_TABLE_NAME'}, $data->{'UK_TABLE_NAME'}, $data->{'UK_TABLE_NAME'}, $data->{'UK_COLUMN_NAME'}) {
                    s/"|'//g;
                }

                $fk = UR::DataSource::RDBMS::FkConstraint->create(
                    fk_constraint_name => $data->{'FK_NAME'},
                    table_name      => $data->{'FK_TABLE_NAME'},
                    r_table_name    => $data->{'UK_TABLE_NAME'},
                    owner           => $table_object->{owner},
                    r_owner         => $table_object->{owner},
                    data_source     => $table_object->{data_source},
                    last_object_revision => $revision_time,
                );
    
                $fk{$fk->id} = $fk;
            }
    
            if ($fk{$fk->id}) {
                my $fkcol = UR::DataSource::RDBMS::FkConstraintColumn->get_or_create(
                    fk_constraint_name => $data->{'FK_NAME'},
                    table_name      => $data->{'FK_TABLE_NAME'},
                    column_name     => $data->{'FK_COLUMN_NAME'},
                    r_table_name    => $data->{'UK_TABLE_NAME'},
                    r_column_name   => $data->{'UK_COLUMN_NAME'},
                    owner           => $table_object->{owner},
                    data_source     => $table_object->{data_source},
                );
                    
            }
    
            push @constraints, $fk;
        }
    }

    # get foreign_key_info the other way
    # constraints on this table against columns in other tables

    my $fk_reverse_sth = $data_source->get_foreign_key_details_from_data_dictionary('', '', '', '', $db_owner, $table_name);

    %fk = ();   # resetting this prevents data_source referencing
                # tables from fouling up their fk objects


    if ($fk_reverse_sth) {
        while (my $data = $fk_reverse_sth->fetchrow_hashref()) {

            foreach ( qw( FK_TABLE_NAME UK_TABLE_NAME FK_NAME FK_COLUMN_NAME UK_COLUMN_NAME ) ) {
                $data->{$_} = uc($data->{$_});
            }

            my $fk = UR::DataSource::RDBMS::FkConstraint->get(fk_constraint_name => $data->{'FK_NAME'},
                                                              table_name => $data->{'FK_TABLE_NAME'},
                                                              r_table_name => $data->{'UK_TABLE_NAME'},
                                                              data_source => $table_object->{'data_source'},
                                                            );
            unless ($fk) {
                # Postgres puts quotes around things that look like keywords
                foreach ( $data->{'FK_TABLE_NAME'}, $data->{'UK_TABLE_NAME'}, $data->{'UK_TABLE_NAME'}, $data->{'UK_COLUMN_NAME'}) {
                    s/"|'//g;
                }

                $fk = UR::DataSource::RDBMS::FkConstraint->create(
                    fk_constraint_name => $data->{'FK_NAME'},
                    table_name      => $data->{'FK_TABLE_NAME'},
                    r_table_name    => $data->{'UK_TABLE_NAME'},
                    owner           => $table_object->{owner},
                    r_owner         => $table_object->{owner},
                    data_source     => $table_object->{data_source},
                    last_object_revision => $revision_time,
                );
                unless ($fk) {
                    #$DB::single=1;
                    1;
                }
                $fk{$fk->fk_constraint_name} = $fk;
            }
    
            if ($fk{$fk->fk_constraint_name}) {
                 UR::DataSource::RDBMS::FkConstraintColumn->get_or_create(
                    fk_constraint_name => $data->{'FK_NAME'},
                    table_name      => $data->{'FK_TABLE_NAME'},
                    column_name     => $data->{'FK_COLUMN_NAME'},
                    r_table_name    => $data->{'UK_TABLE_NAME'},
                    r_column_name   => $data->{'UK_COLUMN_NAME'},
                    owner           => $table_object->{owner},
                    data_source     => $table_object->{data_source},
                 );
            }
    
                
            push @constraints, $fk;
        }
    }

    # get primary_key_info

    my $pk_sth = $data_source->get_primary_key_details_from_data_dictionary(undef, $db_owner, $table_name);

    if ($pk_sth) {
		my @new_pk;
        while (my $data = $pk_sth->fetchrow_hashref()) {
            $data->{'COLUMN_NAME'} =~ s/"|'//g;  # Postgres puts quotes around things that look like keywords
            my $pk = UR::DataSource::RDBMS::PkConstraintColumn->get(
                            table_name => $table_name,
                            data_source => $data_source,
                            column_name => $data->{'COLUMN_NAME'},
                          );
            if ($pk) {
				# Since the rank/order is pretty much all that might change, we
				# just delete and re-create these.
				# It's a no-op at save time if there are no changes.
            	$pk->delete;
            }
			
			push @new_pk, [
				table_name => $table_name,
				data_source => $data_source,
				owner => $data_source->owner,
				column_name => $data->{'COLUMN_NAME'},
				rank => $data->{'KEY_SEQ'} || $data->{'ORDINAL_POSITION'},
			];
			#        $table_object->{primary_key_constraint_name} = $data->{PK_NAME};
			#        $embed{primary_key_constraint_column_names} ||= {};
			#        $embed{primary_key_constraint_column_names}{$table_object} ||= [];
			#        push @{ $embed{primary_key_constraint_column_names}{$table_object} }, $data->{COLUMN_NAME};
        }
		
		for my $data (@new_pk) {
        	my $pk = UR::DataSource::RDBMS::PkConstraintColumn->create(@$data);
			unless ($pk) {
				$self->error_message("Failed to create primary key @$data");
				return;
			}
		}			
    }

    ## Get the unique constraints
    ## Unfortunately, there appears to be no DBI catalog
    ## method which will find these.  So we have to use
    ## some custom SQL
    #
    # The SQL that used to live here was moved to the UR::DataSource::Oracle
    # and each other DataSource class needs its own implementation

    # The above was moved into each data source's class
    if (my $uc = $data_source->get_unique_index_details_from_data_dictionary($table_name)) {
        my %uc = %$uc;

        # check for redundant unique constraints
        # there may be both an index and a constraint

        for my $uc_name_1 ( keys %uc ) {

            my $uc_columns_1 = $uc{$uc_name_1}
                or next;
            my $uc_columns_1_serial = join ',', sort @$uc_columns_1;

            for my $uc_name_2 ( keys %uc ) {
                next if ( $uc_name_2 eq $uc_name_1 );
                my $uc_columns_2 = $uc{$uc_name_2}
                    or next;
                my $uc_columns_2_serial = join ',', sort @$uc_columns_2;

                if ( $uc_columns_2_serial eq $uc_columns_1_serial ) {
                    delete $uc{$uc_name_1};
                }
            }
        }

        # compare primary key constraints to unique constraints
        my $pk_columns_serial = join(',', sort map { $_->column_name }
                                            UR::DataSource::RDBMS::PkConstraintColumn->get(data_source => $data_source,
                                                                                           table_name => $table_name,
                                                                                           owner => $data_source->owner,
                                                                                         ));
        for my $uc_name ( keys %uc ) {

            # see if primary key constraint has the same name as
            # any unique constraints
            # FIXME - disabling this for now, the Meta DB dosen't track PK constraint names
            # Isn't it just as goot to check the involved columns?
            #if ( $table_object->primary_key_constraint_name eq $uc_name ) {
            #    delete $uc{$uc_name};
            #    next;
            #}

            # see if any unique constraints cover the exact same column(s) as
            # the primary key column(s)
            my $uc_columns_serial = join ',',
                sort @{ $uc{$uc_name} };

            if ( $pk_columns_serial eq $uc_columns_serial ) {
                delete $uc{$uc_name};
            }
        }

        # Create new UniqueConstraintColumn objects for the columns that don't exist, and delete the
        # objects if they don't apply anymore
        foreach my $uc_name ( keys %uc ) {
            my %constraint_objs = map { $_->column_name => $_ } UR::DataSource::RDBMS::UniqueConstraintColumn->get(
                                                                            data_source => $data_source,
                                                                            table_name => $table_name,
                                                                            owner => $data_source->owner || '',
                                                                            constraint_name => $uc_name,
                                                                          );
    
            foreach my $col_name ( @{$uc{$uc_name}} ) {
                if ($constraint_objs{$col_name} ) {
                    delete $constraint_objs{$col_name};
                } else {
                    my $uc = UR::DataSource::RDBMS::UniqueConstraintColumn->create(
                                                   data_source => $data_source,
                                                   table_name => $table_name,
                                                   owner => $data_source->owner,
                                                   constraint_name => $uc_name,
                                                   column_name => $col_name,
                                              );
                     1;
                }
            } 
            foreach my $obj ( values %constraint_objs ) {
                $obj->delete();
            }
        }
    }

#    # embed the data structures;
#    my %str_to_obj;
#    for my $obj ($table_object, @column_objects, @constraints) {
#        $str_to_obj{$obj} = $obj;
#    }
#    use Data::Dumper;
#    my $useqq_orig = $Data::Dumper::Useqq;
#    for my $method_basename (keys %embed) {
#        my $objects = $embed{$method_basename};
#        for my $obj_str (keys %$objects) {
#            my $data = $objects->{$obj_str};
#            $Data::Dumper::Useqq = 1;
#            my $src = Dumper($data);
#            $src =~ s/^\$VAR1 = //;
#            $src =~ s/\s+//gs;
#            $Data::Dumper::Useqq = $useqq_orig;
#            my $obj = $str_to_obj{$obj_str};
#            my $method_fullname =
#                "x_" . $method_basename
#                . (ref($data) eq "HASH" ? "_hash" : "_array");
#            #print "setting $method_fullname on $obj to $src\n";
#            $obj->$method_fullname($src);
#        }
#    }

    # Now that all columns know their foreign key constraints,
    # have the column objects resolve the various names
    # associated with the column.

    #for my $col (@column_objects) { $col->resolve_names }

    # Determine the ER type.
    # We have 'validation item', 'entity', and 'bridge'

    my $column_count = scalar($table_object->column_names) || 0;
    my $pk_column_count = scalar($table_object->primary_key_constraint_column_names) || 0;
    my $constraint_count = scalar($table_object->fk_constraint_names) || 0;

    if ($column_count == 1 and $pk_column_count == 1)
    {
        $table_object->er_type('validation item');
    }
    else
    {
        if ($constraint_count == $column_count)
        {
            $table_object->er_type('bridge');
        }
        else
        {
            $table_object->er_type('entity');
        }
    }

    return $table_object;
}



1;

