package UR::Namespace::Command::Describe;
use strict;
use warnings;
use UR;
our $VERSION = "0.30"; # UR $VERSION;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command::RunsOnModulesInTree',
    has => [
        classes_or_modules => {
            is_optional => 0,
            is_many => 1,
            shell_args_position => 99,
            doc => 'classes to describe by class name or module path',
        },
    ],
    doc => 'show class properties, relationships, meta-data',
);

sub sub_command_sort_position { 3 }

sub help_synopsis {
    return <<EOS
ur describe UR::Object

ur describe Acme::Order Acme::Product Acme::Order::LineItem

EOS
}

# The class metadata has lots of properties that we're not interested in
our @CLASS_PROPERTIES_NOT_TO_PRINT = qw(
    generated
    short_name
    is
    all_class_metas
);
    
sub for_each_class_object {
    my $self = shift;
    my $class_meta = shift;

    my $view = UR::Object::Type->create_view(
                    perspective => 'default',
                    toolkit => 'text',
                    aspects => [
                        'namespace', 'table_name', 'data_source_id', 'is_abstract', 'is_final',
                        'is_singleton', 'is_transactional', 'schema_name', 'meta_class_name',
                        'first_sub_classification_method_name', 'sub_classification_method_name',
                        {
                            label => 'Properties',
                            name => 'properties',
                            subject_class_name => 'UR::Object::Property',
                            perspective => 'description line item',
                            toolkit => 'text',
                            aspects => ['is_id', 'property_name', 'column_name', 'data_type', 'is_optional' ],
                        },
                        {
                            label => "References",
                            name => 'all_id_by_property_metas',
                            subject_class_name => 'UR::Object::Property',
                            perspective => 'reference description',
                            toolkit => 'text',
                            aspects => [],
                        },
                        {
                            label => "Referents",
                            name => 'all_reverse_as_property_metas',
                            subject_class_name => 'UR::Object::Property',
                            perspective => 'reference description',
                            toolkit => 'text',
                            aspects => [],
                        },
                    ],
                );
    unless ($view) {
        $self->error_message("Can't initialize view");
        return;
    }

    $view->subject($class_meta);
    $view->show();
}

1;
