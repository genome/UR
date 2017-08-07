package Command::Create;

use strict;
use warnings;

use YAML;

class Command::Create {
    is => 'Command::V2',
    is_abstract => 1,
    has_constant => {
        target_class => { via => 'namespace', to => 'target_class', },
    },
    doc => 'CRUD create command class.',
};

sub help_brief { $_[0]->__meta__->doc }
sub help_detail { $_[0]->__meta__->doc }

sub execute {
    my $self = shift;

    my %properties;
    for my $property_name ( @{$self->target_class_properties} ) {
        my @values = $self->$property_name;
        next if not defined $values[0];
        my $property = $self->__meta__->property_meta_for_name($property_name);
        if ( $property->is_many ) {
            $properties{$property_name} = \@values;
        }
        else {
            $properties{$property_name} = $values[0];
        }
    }

    $self->status_message("Params:");
    $self->status_message( YAML::Dump({ map { $_ => Command::CrudUtil->display_name_for_value($properties{$_}) } keys %properties }) );
    my $target_class = $self->target_class;

    my $tx = UR::Context::Transaction->begin;
    my $obj = $target_class->create(%properties);
    $self->fatal_message('Create failed!') if not $obj;

    if (!$tx->commit ) {
        $tx->rollback;
        $self->fatal_message('Failed to commit software transaction!');
    }

    $self->status_message("New\t%s\t%s", $obj->class, $obj->__display_name__);
    1;
}

1;
