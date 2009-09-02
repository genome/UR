package UR::Object::Type::Viewer::Default::Text;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::Viewer',
);


# These are noops for textual widgets
sub _update_subject_from_widget {
1;}

#sub show {
#my $self = shift;
#
#    print $self->sshow();
#}

sub _create_widget {
    my $string = '';
    return \$string;
}


# For now, it's not looking at the aspects requested by the caller, and it
# just prints what is required to get "ur info" working
sub _update_widget_from_subject {
my $self = shift;

    my $class = $self->get_subject();
    my @aspects = $self->get_aspects();
    my $widget = $self->get_widget();
  
    my $string = "Class " . $class->class_name;
    if ($class->table_name) {
        $string .= "  Table " . $class->table_name . "\n";
    } else {
        $string .= "  no related table\n";
    }

    my %all_class_properties = map { $_ => 1 } $class->get_class_object->all_property_names;

    # Print these first
    my @prop_list = qw(is data_source table_name doc);
    foreach my $item ( @prop_list )  {
        my $val = eval { $class->$item };
        next unless defined $val;
        $string .= sprintf("    %16s  %s\n", $item, $val);
    }

    delete @all_class_properties{@prop_list};
    delete @all_class_properties{('id_by','is','class_name','source')};
    foreach my $item ( sort keys %all_class_properties ) {
        my $val = eval { $class->$item };
        next unless defined $val;
        $string .= sprintf("    %16s  %s\n", $item, $val);
    }

    $string .= "\nInheritance\n";
    $string .= join("\n", map { "\t$_" } reverse $class->inheritance);
    $string .= "\n";

    my @properties = sort { $a->property_name cmp $b->property_name } $class->get_all_property_objects;
    my %id_properties = map { $_ => 1 } $class->all_id_property_names;
    $string .= "\nProperties\n" if (@properties);
    foreach my $property ( @properties ) {
        my $nullable = $property->is_optional ? "NULLABLE" : "";
        my $column_name = $property->column_name ? $property->column_name : "(no column)";
        my $data_type_string;
        if (defined $property->data_type) {
            $data_type_string = $property->data_type . ( $property->data_length ? "(".$property->data_length.")" : "");
        } else {
            $data_type_string = "";
        }
        $string .= sprintf(" %2s %25s  %-25s %15s $nullable\n",
                           $id_properties{$property->property_name} ? "ID" : "  ",
                           $property->property_name,
                           $column_name,
                           $data_type_string,
                          );
    }

    my @relationships = UR::Object::Reference->get(class_name => $class->class_name);
    $string .= "\nRelationships\n" if (@relationships);
    foreach my $rel ( @relationships ) {
        my @rel_detail;
        foreach my $rel_prop ( UR::Object::Reference::Property->get(tha_id => $rel->tha_id) ) {
            my $property_name = $rel_prop->property_name;
            my $r_property_name = $rel_prop->r_property_name;
            push @rel_detail, $rel->r_class_name . "->get($r_property_name => \$self->$property_name)";
        }

        $string .= sprintf("    %20s => %s\n", $rel->delegation_name, shift @rel_detail);
        while (@rel_detail) {
            $string .=  " "x28 . shift(@rel_detail) . "\n";
        }
    }

    $$widget = $string;
}

1;    
