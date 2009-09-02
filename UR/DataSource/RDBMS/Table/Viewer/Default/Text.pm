package UR::DataSource::RDBMS::Table::Viewer::Default::Text;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::Viewer',
);

# These are noops for stdout widgets
sub _update_subject_from_widget {
1;}

# Maybe this is common for all text widgets
sub _create_widget {
    my $string = '';
    return \$string;
}


# Like show(), but returns the data as a string that would have been printed
# in the same way sprintf returns what printf would have printed
#
# For now, we're ignoring the aspects the caller requested, and just
# print what's required for "ur info" to work
sub _update_widget_from_subject {
my $self = shift;

$DB::single=1;
    my $table_obj = $self->get_subject();
    my @aspects = $self->get_aspects();
    my $widget = $self->get_widget();

    my $string = "";

    my $namespace = $table_obj->data_source->get_namespace;

    my $table_name = $table_obj->table_name;

    $string .= "Table $table_name\n";
    $string .= "Related class: " . $table_obj->handler_class_name(namespace => $namespace) . "\n";
    
    foreach my $prop ( qw(data_source owner last_ddl_time remarks) ) {
        $string .= "$prop: " . $table_obj->$prop . "\n";
    }
     
    my %primary_keys = map { $_ => 1 } $table_obj->primary_key_constraint_column_names;
    foreach my $column_obj ( UR::DataSource::RDBMS::TableColumn->get(table_name => $table_name)
                          ) {
        my $column_name = $column_obj->column_name();

        my $data_type_string = '';
        if (defined $column_obj->data_type) {
            $data_type_string = $column_obj->data_type . ( $column_obj->data_length ? "(".$column_obj->data_length.")" : "");
        }
 
        my $fk_string = '';
        my $fk_obj = UR::DataSource::RDBMS::FkConstraintColumn->get(table_name => $table_name,
                                                                    column_name => $column_name);
        if ($fk_obj) {
            $fk_string = sprintf('FK-> %s.%s',$fk_obj->r_table_name, $fk_obj->r_column_name);
        }

        $string .= sprintf(" %2s %25s %-15s %8s %s\n",
                           $primary_keys{$column_name} ? "PK" : "",
                           $column_name,
                           $data_type_string,
                           $column_obj->nullable eq 'N' ? 'NOT NULL' : '',
                           $fk_string);
    }

    my @ref_fks = $table_obj->ref_fk_constraints();
    if (@ref_fks) {
        $string .= "Referring Tables: " . join(',',sort map { $_->table_name } @ref_fks) . "\n";
    }

    
    $$widget = $string;
}
 
1;
