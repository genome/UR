
package UR::Namespace::Command::Describe;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command::RunsOnModulesInTree'
);


sub help_brief {
    "Outputs class description(s) to stdout.";
}

sub for_each_class_object {
    my $self = shift;
    my $class = shift;

    print $class->class_name;

    my @parent_class_names = grep { $_ !~ qr/^(UR::Object|UR::Object|UR::Entity)$/ }$class->parent_class_names;
    if (@parent_class_names) {
        print " < @parent_class_names"
    }

    print "\n  Class:\n";
    
    my %all_class_properties = map { $_ => 1 } $class->get_class_object->all_property_names;

    # Print these first
    my @prop_list = qw(is data_source table_name doc);
    foreach my $item ( @prop_list )  {
        my $val = eval { $class->$item };
        next unless defined $val;
        printf("    %16s  %s\n", $item, $val);
    }
    
    delete @all_class_properties{@prop_list};
    delete @all_class_properties{('id_by','is','class_name','source')};
    foreach my $item ( sort keys %all_class_properties ) {
        my $val = eval { $class->$item };
        if ($item =~ /^is_/) {
            $val = ($val ? "TRUE" : "FALSE");
        }
        next unless defined $val;
        printf("    %16s  %s\n", $item, $val);
    }

    
    my %id_properties = map { $_ => 1 } $class->all_id_property_names;
    my @properties = 
        sort { 
            defined($id_properties{$a}) cmp defined($id_properties{$b})
            ||
            $a->property_name cmp $b->property_name 
        } 
        $class->get_all_property_objects;
    print "\n  Properties:\n" if (@properties);
    foreach my $property ( @properties ) {
        my $nullable = $property->is_optional ? "NULLABLE" : "";
        my $column_name = $property->column_name ? $property->column_name : "(no column)";
        my $data_type_string;
        if (defined $property->data_type) {
            $data_type_string = $property->data_type . ( $property->data_length ? "(".$property->data_length.")" : "");
        } else {
            $data_type_string = "";
        }
        printf(" %2s %25s  %-25s %15s $nullable\n", 
               $id_properties{$property->property_name} ? "ID" : "  ",
               $property->property_name,
               $column_name,
               $data_type_string,
              );
    }


    my @relationships = UR::Object::Reference->get(class_name => $class->class_name);
    print "\n  Relationships:\n" if (@relationships);
    foreach my $rel ( @relationships ) {
        my $r_class_name = $rel->r_class_name;
        if (grep { $_ eq $r_class_name } @parent_class_names) {
            # inheritance is already shown
            next;
        }
        my @rel_detail;
        foreach my $rel_prop ( UR::Object::Reference::Property->get(tha_id => $rel->tha_id) ) {
            my $property_name = $rel_prop->property_name;
            my $r_property_name = $rel_prop->r_property_name;
            push @rel_detail, $rel->r_class_name . "->get($r_property_name => \$self->$property_name)";
        }

        printf("    %20s => %s\n", $rel->delegation_name, shift @rel_detail);
        while (@rel_detail) {
            print " "x28, shift @rel_detail,"\n";
        }
    }

    return 1;
}

1;
