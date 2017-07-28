package Command::Crud;

use strict;
use warnings 'FATAL';

use Command::CrudUtil;
use Lingua::EN::Inflect;
use List::MoreUtils;
use Sub::Install;

class Command::Crud {
    id_by => {
        target_class => { is => 'Text' },
    },
    has => {
        namespace => { is => 'Text', },
        target_name => { is => 'Text', },
        target_name_pl => { is => 'Text', },
        subcommand_configs => { is => 'HASH', default_value => {}, },
    },
    has_calculated => {
        target_name_ub => {
            calculate_from => [qw/ target_name /],
            calculate => q( $target_name =~ s/ /_/g; $target_name; ),
        },
        target_name_ub_pl => {
            calculate_from => [qw/ target_name_pl /],
            calculate => q( $target_name_pl =~ s/ /_/g; $target_name_pl; ),
        },
        copy_command_class_name => {
            calculate_from => [qw/ namespace /],
            calculate => q( $namespace.'::Copy' ),
        },
        create_command_class_name => {
            calculate_from => [qw/ namespace /],
            calculate => q( $namespace.'::Create' ),
        },
        list_command_class_name => {
            calculate_from => [qw/ namespace /],
            calculate => q( $namespace.'::List' ),
        },
        update_command_class_name => {
            calculate_from => [qw/ namespace /],
            calculate => q( $namespace.'::Update' ),
        },
        delete_command_class_name => {
            calculate_from => [qw/ namespace /],
            calculate => q( $namespace.'::Delete' ),
        },
    },
    doc => 'Dynamically build CRUD commands',
};

#sub buildable_subcommand_names { (qw/ copy create delete list update /) }
sub subcommand_config_for {
    my ($self, $name) = @_;

    $self->fatal_message('No subcommand name given to get config!') if not $name;

    my $subcommand_configs = $self->subcommand_configs;
    return if !exists $subcommand_configs->{$name};

    if ( ref($subcommand_configs->{$name}) ne 'HASH' ) {
        $self->fatal_message('Invalid subcommand config for %s: %s', $name, Data::Dumper::Dumper($subcommand_configs->{$name}));
    }

    %{$subcommand_configs->{$name}}; # copy hash
}

sub create_command_subclasses {
    my ($class, %params) = @_;

    $class->fatal_message('No target_class given!') if not $params{target_class};

    my $self = $class->create(%params);
    return if not $self;

    $self->namespace( $self->target_class.'::Command' ) if not $self->namespace;
    $self->_resolve_target_names;

    my @errors = $self->__errors__;
    $self->fatal_message( join("\n", map { $_->__display_name__ } @errors) ) if @errors;

    print Data::Dumper::Dumper($self);

    return $self;
    # Get the current sub commands
    my @namespace_sub_command_classes = $self->namespace->sub_command_classes;
    my @namespace_sub_command_names = $self->namespace->sub_command_names;
    # FIXME add subcommands
    my (@command_names_used, @command_classes);

    $self->_build_command_tree;
    $self->_build_create_command;
    $self->_build_list_command;
    $self->_build_update_command;
    $self->_build_delete_command;

        #*{ $sub_class.'::_display_name_for_value' } = \&display_name_for_value;

    # Overload sub command classes to return these in memory ones, plus the existing ones
    my @sub_command_classes = List::MoreUtils::uniq @command_classes, @namespace_sub_command_classes;
    Sub::Install::install_sub({
        code => sub{ @sub_command_classes },
        into => $self->namespace,
        as => 'sub_command_classes',
        });

    my @sub_command_names = List::MoreUtils::uniq  @command_names_used, @namespace_sub_command_names;
    Sub::Install::install_sub({
        code => sub{ @sub_command_names },
        into => $self->namespace,
        as => 'sub_command_names',
        });

    $self;
}

sub _resolve_target_names {
    my $self = shift;

    if ( !$self->target_name ) {
        $self->target_name( join(' ', map { Command::CrudUtil->camel_case_to_string($_) } split('::', $self->target_class)) );
    }

    if ( !$self->target_name_pl ) {
        Lingua::EN::Inflect::classical(persons => 1);
        $self->target_name_pl( Lingua::EN::Inflect::PL($self->target_name) );
    }
}

sub _build_command_tree {
    my $self = shift;

    return if UR::Object::Type->get($self->namespace);

    UR::Object::Type->define(
        class_name => $self->namespace,
        is => 'Command::Tree',
        doc => 'work with '.$self->target_name_pl,
    );
}

sub _build_list_command {
    my $self = shift;

    my $list_command_class_name = $self->list_command_class_name;
    return if UR::Object::Type->get($list_command_class_name); # Do not recreate...

    my %config = $self->subcommand_config_for('list');
    return if exists $config{skip}; # Do not create if told not too...

    my @has =  (
        subject_class_name  => {
            is_constant => 1,
            value => $self->target_class,
        },
    );

    my $show = delete $config{show};
    if ( $show ) {
        push @has, show => { default_value => $show, };
    }

    my $order_by = delete $config{order_by};
    if ( $order_by ) {
        push @has, order_by => { default_value => $order_by, };
    }

    $self->fatal_message('Unknown config for LIST: %s', Data::Dumper::Dumper(\%config)) if %config;

    UR::Object::Type->define(
        class_name => $list_command_class_name,
        is => 'UR::Object::Command::List',
        has => \@has,
    );

    Sub::Install::install_sub({
        code => sub{ $self->target_name_pl },
        into => $list_command_class_name,
        as => 'help_brief',
        });
}

sub _build_create_command {
    my $self = shift;

    my $create_command_class_name = $self->create_command_class_name;
    return if UR::Object::Type->get($create_command_class_name); # Do not recreate...

    my %config = $self->subcommand_config_for('create');
    return if exists $config{skip}; # Do not create if told not too...

    my @exclude = Command::CrudUtil->resolve_incoming_property_names( delete $config{exclude} );
    $self->fatal_message('Unknown config for LIST: %s', Data::Dumper::Dumper(\%config)) if %config;

    my $target_meta = $self->target_class->__meta__;
    my %properties;
    for my $target_property ( $target_meta->property_metas ) {
        my $property_name = $target_property->property_name;

        next if grep { $property_name eq $_ } @exclude;
        next if $target_property->class_name eq 'UR::Object';
        next if $property_name =~ /^_/;
        next if grep { $target_property->$_ } (qw/ is_calculated is_constant is_transient /);
        next if $target_property->is_id and ($property_name eq 'id' or $property_name =~ /_id$/);
        next if grep { not $target_property->$_ } (qw/ is_mutable /);
        next if $target_property->is_many and $target_property->is_delegated and not $target_property->via; # direct relationship

        my %property = (
            property_name => $property_name,
            data_type => $target_property->data_type,
            is_many => $target_property->is_many,
            is_optional => $target_property->is_optional,
            valid_values => $target_property->valid_values,
            default_value => $target_property->default_value,
            doc => $target_property->doc,
        );

        if ( $property_name =~ s/_id(s)?$// ) {
            $property_name .= $1 if $1;
            my $object_meta = $target_meta->property_meta_for_name($property_name);
            if ( $object_meta and  not grep { $object_meta->$_ } (qw/ is_calculated is_constant is_transient id_class_by /) ) {
                $property{property_name} = $property_name;
                $property{data_type} = $object_meta->data_type;
                $property{doc} = $object_meta->doc if $object_meta->doc;
            }
        }

        $properties{$property{property_name}} = \%property;
    }

    $self->fatal_message('No properties found for target class: '.$config{target_class}) if not %properties;

    my $create_meta = UR::Object::Type->define(
        class_name => $create_command_class_name,
        is => 'Command::Create',
        has => \%properties,
        doc => 'create '.$config{target_name_pl},
    );

    no strict;
    *{$create_command_class_name.'::_target_class'} = sub{ return $config{target_class}; };
    *{$create_command_class_name.'::_target_name'} = sub{ return $config{target_name}; };
    *{$create_command_class_name.'::_before'} = $config{before} if $config{before};
}

sub _build_copy_command {
    my $self = shift;

    my $copy_command_class_name = $self->copy_command_class_name;
    return if UR::Object::Type->get($copy_command_class_name);
    
    my %config = $self->subcommand_config_for('copy');
    return if exists $config{skip}; # Do not create if told not too...

    UR::Object::Type->define(
        class_name => $copy_command_class_name,
        is => 'Genome::Command::Copy',
        doc => sprintf('copy a %s', $self->target_name),
        has => {
            source => {
                is => $self->target_class,
                shell_args_position => 1,
                doc => sprintf('the source %s to copy from', $self->target_name),
            },
        },
    );

    #$self->_add_to_created_commands($copy_command_class_name);
}

sub _build_update_command {
    my $self = shift;

    my $update_command_class_name = $self->update_command_class_name;
    return if UR::Object::Type->get($update_command_class_name);

    my %config = $self->subcommand_config_for('copy');
    return if exists $config{skip}; # Do not create if told not too...

    # Config
    # include only these properties
    my @include_only = Command::CrudUtil->resolve_incoming_property_names( delete $config{include_only} );
    my @exclude = Command::CrudUtil->resolve_incoming_property_names( delete $config{exclude} );
    if ( @include_only and @exclude ) {
        $self->fatal_message('Cannot include only and exclude update sub commands!');
    }

    # only if null
    my (%only_if_null, $all_only_if_null);
    if ( my $only_if_null = delete $config{only_if_null} ) {
        my $ref = ref $only_if_null;
        if ( $only_if_null eq 1 ) {
            $all_only_if_null = 1;
        }
        elsif ( not $ref ) {
            Carp::confess("Unknown 'only_if_null' config: $only_if_null");
        }
        else {
            %only_if_null = map { $_ => 1 } map { s/_id$//; $_; } ( $ref eq 'ARRAY' ? @$only_if_null : keys %$only_if_null )
        }
    }

    # Update tree
    my $update_meta = $update_command_class_name->__meta__;
    my (@update_sub_commands, @update_sub_command_names);
    if ( not $update_meta ) {
        UR::Object::Type->define(
            class_name => $update_command_class_name,
            is => 'Genome::Command::UpdateTree',
            doc => 'properties on '.$self->target_name_pl,
        );
    }
    else { # update command tree exists
        @update_sub_commands = $update_command_class_name->sub_command_classes;
        @update_sub_command_names = $update_command_class_name->sub_command_names;
    }

    # Properties make a command for each
    my $target_meta = $self->target_class->__meta__;
    my %properties_seen;
    PROPERTY: for my $target_property ( $target_meta->property_metas ) {
        my $property_name = $target_property->property_name;
        next if grep { $property_name eq $_ } @update_sub_command_names;
        next if @include_only and not grep { $property_name =~ /^$_(_id)?$/ } @include_only;
        next if @exclude and grep { $property_name =~ /^$_(_id)?$/ } @exclude;

        next if $target_property->class_name eq 'UR::Object';
        next if $property_name =~ /^_/;
        next if grep { $target_property->$_ } (qw/ is_id is_calculated is_constant is_transient /);
        next if grep { not $target_property->$_ } (qw/ is_mutable /);
        next if $target_property->is_many and $target_property->is_delegated and not $target_property->via; # direct relationship

        my %property = (
            name => $target_property->singular_name,
            name_pl => $target_property->plural_name,
            is_many => $target_property->is_many,
            data_type => $target_property->data_type,
            doc => $target_property->doc,
        );
        $property{valid_values} = $target_property->valid_values if defined $target_property->valid_values;

        if ( $property_name =~ s/_id(s)?$// ) {
            $property_name .= $1 if $1;
            my $object_meta = $target_meta->property_meta_for_name($property_name);
            if ( $object_meta ) {
                next if grep { $object_meta->$_ } (qw/ is_calculated is_constant is_transient id_class_by /);
                $property{name} = $object_meta->singular_name;
                $property{name_pl} = $object_meta->plural_name;
                $property{is_optional} = $object_meta->is_optional;
                $property{data_type} = $object_meta->data_type;
                $property{doc} = $object_meta->doc if $object_meta->doc;
            }
        }
        next if $properties_seen{$property_name};
        $properties_seen{$property_name} = 1;

        $config{property} = \%property;
        $config{only_if_null} = ( $all_only_if_null or exists $only_if_null{$property_name} ) ? 1 : 0;
        my $update_sub_command;
        if ( $property{is_many} ) {
            $update_sub_command = $self->_build_add_remove_property_sub_commands(%config);
        }
        else {
            $update_sub_command = $self->_build_update_property_sub_command(%config);
        }
        push @update_sub_commands, $update_sub_command if $update_sub_command;
    }

    no strict;
    *{$update_class_name.'::sub_command_classes'} = sub{ return @update_sub_commands; };

    $update_class_name;
}

sub _build_update_property_sub_command {
    my $self = shift;
    my ($class, %config) = @_;

    my $property = $config{property};
    my $update_property_class_name = $config{namespace}.'::Update::'.join('', map { ucfirst } split('_', $property->{name}));
    my $update_property_class = eval{ $update_property_class_name->class; };
    return if $update_property_class; # OK

    UR::Object::Type->define(
        class_name => $update_property_class_name,
        is => 'Genome::Command::UpdateProperty',
        has => [
            $self->target_name_ub_pl => {
                is => $self->target_class,
                is_many => 1,
                shell_args_position => 1,
                doc => ucfirst($self->target_name_pl).' to update, resolved via string.',
            },
            value => {
                is => $property->{data_type},
                valid_values => $property->{valid_values},
                doc => $property->{doc},
            },
        ],
        doc => 'update '.$self->target_name_pl.' '.$property->{name},
    );

    no strict;
    *{ $update_property_class_name.'::_target_name_pl' } = sub{ return $config{target_name_pl}; };
    *{ $update_property_class_name.'::_target_name_pl_ub' } = sub{ return $config{target_name_ub_pl}; };
    *{ $update_property_class_name.'::_property_name' } = sub{ return $property->{name}; };
    *{ $update_property_class_name.'::_property_doc' } = sub{ return $property->{doc}; } if $property->{doc};
    *{ $update_property_class_name.'::_only_if_null' } = sub{ return $config{only_if_null}; };
    *{ $update_property_class_name.'::_display_name_for_value' } = \&display_name_for_value;

    return $update_property_class_name;
}

sub _build_add_remove_property_sub_commands {
    my $self = shift;
    my ($class, %config) = @_;

    my $property = $config{property};
    my $update_tree_class_name = $config{namespace}.'::Update::'.join('', map { ucfirst } split('_', $property->{name_pl}));
    UR::Object::Type->define(
        class_name => $update_tree_class_name,
        is => 'Command::Tree',
        doc => 'add/remove '.$property->{name_pl},
    );

    my @update_sub_command_class_names;
    no strict;
    *{$update_tree_class_name.'::_target_name'} = sub{ return $config{target_name}; };
    *{$update_tree_class_name.'::_target_name_ub'} = sub{ return $config{target_name_ub}; };
    *{$update_tree_class_name.'::_property_name'} = sub{ return $property->{name}; };
    *{$update_tree_class_name.'::_property_name_pl'} = sub{ return $property->{name_pl}; };
    *{$update_tree_class_name.'::_display_name_for_value'} = \&display_name_for_value;
    *{$update_tree_class_name.'::sub_command_classes'} = sub{ return @update_sub_command_class_names; };
    use strict;

    for my $function (qw/ add remove /) {
        my $update_sub_command_class_name = $update_tree_class_name.'::'.ucfirst($function);
        push @update_sub_command_class_names, $update_sub_command_class_name;
        UR::Object::Type->define(
            class_name => $update_sub_command_class_name,
            is => 'Genome::Command::AddRemoveProperty',
            has => {
                $self->target_name_ub_pl => {
                    is => $config{target_class},
                    is_many => 1,
                    shell_args_position => 1,
                    doc => ucfirst($self->target_name_pl).' to update, resolved via string.',
                },
                'values' => => {
                    is => $property->{data_type},
                    is_many => 1,
                    valid_values => $property->{valid_values},
                    doc => $property->{doc},
                },
            },
            doc => $self->target_name_pl.' '.$function.' '.$property->{name_pl},
        );
        no strict;
        *{$update_sub_command_class_name.'::_add_or_remove'} = sub{ return $function; };
        *{$update_sub_command_class_name.'::_target_name'} = sub{ return $config{target_name}; };
        *{$update_sub_command_class_name.'::_target_name_pl'} = sub{ return $config{target_name_pl}; };
        *{$update_sub_command_class_name.'::_target_name_pl_ub'} = sub{ return $config{target_name_ub_pl}; };
        *{$update_sub_command_class_name.'::_property_name'} = sub{ return $property->{name}; };
        *{$update_sub_command_class_name.'::_property_name_pl'} = sub{ return $property->{name_pl}; };
        *{$update_sub_command_class_name.'::_display_name_for_value'} = \&display_name_for_value;
    }

    return $update_tree_class_name;
}

sub _build_delete_command {
    my $self = shift;

    my $delete_command_class_name = $self->delete_command_class_name;
    return if UR::Object::Type->get($self->delete_command_class_name);

    my %config = $self->subcommand_config_for('delete');
    return if exists $config{skip}; # Do not create if told not too...

    UR::Object::Type->define(
        class_name => $delete_command_class_name,
        is => 'Genome::Command::Delete',
        has => {
            $self->target_name_ub_pl => {
                is => $self->target_class,
                is_many => 1,
                shell_args_position => 1,
                require_user_verify => 1,
                doc => ucfirst($self->target_name_pl).' to delete, resolved via text string.',
            },
        },
        doc => 'delete '.$self->target_name_pl,
    );

    Sub::Install::install_sub({
        code => sub{ $self->target_name_pl },
        into => $delete_command_class_name,
        as => '_target_name_pl',
        });

    Sub::Install::install_sub({
        code => sub{ $self->target_name_ub_pl },
        into => $delete_command_class_name,
        as => '_target_name_pl_ub',
        });
    $delete_command_class_name;
}

1;
