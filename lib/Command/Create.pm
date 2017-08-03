package Command::Create;

use strict;
use warnings;

use YAML;

class Command::Create {
    is => 'Command::V2',
    is_abstract => 1,
    has_constant => {
        target_class => { via => 'namespace', to => 'target_class', },
        target_name => { via => 'namespace', to => 'target_name', },
    },
    has_calculated => {
        target_name_a => { calculate_from => [qw/ target_name /], calculate => q| Lingua::EN::Inflect::A($target_name) |, },
    },
    doc => 'CRUD create command class.',
};

sub help_brief { $_[0]->__meta__->doc }
sub help_detail { $_[0]->__meta__->doc }

sub execute {
    my $self = shift;
    $self->status_message('Create '.$self->target_name.'...');

    my %properties;
    for my $property_name ( @{$self->target_class_properties} ) {
        my $property = $self->__meta__->property_meta_for_name($property_name);
        my @values = $self->$property_name;
        next if not defined $values[0];
        if ( $property->is_many ) {
            $properties{$property_name} = \@values;
        }
        else {
            $properties{$property_name} = $values[0];
        }
    }

    $self->status_message( YAML::Dump({ map { $_ => Command::CrudUtil->display_name_for_value($properties{$_}) } keys %properties }) );
    my $target_class = $self->target_class;
    my $obj = $target_class->create(%properties);
    $self->fatal_message('Failed to create %s',  $self->target_name) if not $obj;
    $self->status_message('New %s: %s', $self->target_name, $obj->__display_name__);
    1;
}

1;
