
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


# The class metadata has lots of properties that we're not interested in
our @CLASS_PROPERTIES_NOT_TO_PRINT = qw(
    generated
    short_name
    is
    all_class_metas
);
    
    
our $viewer;
sub for_each_class_object {
    my $self = shift;
    my $class_meta = shift;

$DB::single=1;
    $viewer ||= UR::Object::Viewer->create_viewer(
                    subject_class_name => 'UR::Object::Type',
                    perspective => 'default',
                    toolkit => 'text',
                    aspects => [
                        'namespace', 'table_name', 'data_source_id', 'is_abstract', 'is_final',
                        'is_singleton', 'is_transactional', 'schema_name', 'meta_class_name',
                        'first_sub_classification_method_name', 'sub_classification_method_name',
                        'Properties' => {
                            method => 'all_property_metas',
                            subject_class_name => 'UR::Object::Property',
                            perspective => 'description line item',
                            toolkit => 'text',
                            aspects => ['is_id', 'property_name', 'column_name', 'data_type', 'is_optional' ],
                        },
                        'Relationships' => {
                            method => 'all_reference_metas',
                            subject_class_name => 'UR::Object::Reference',
                            perspective => 'description line item',
                            toolkit => 'text',
                        }
                    ],
                );
    unless ($viewer) {
        $self->error_message("Can't initialize viewer");
        return;
    }

    $viewer->set_subject($class_meta);
    $viewer->show();
    print "\n";
}

    


sub X_for_each_class_object {
    my $self = shift;
    my $class = shift;

$DB::single=1;
    print $class->class_name;

    #my @parent_class_names = grep { $_ !~ qr/^(UR::Object|UR::Entity)$/ } $class->parent_class_names;
    my @parent_class_names = $class->parent_class_names;
    if (@parent_class_names) {
        print " < ", join(' ', @parent_class_names);
    }

    my $class_meta = $class->get_class_object();

    print "\n  Class:\n";
    
    my %all_class_properties = map { $_ => 1 } $class_meta->all_property_names;

    # Print these first
    my %printed;
    my @prop_list = qw(namespace table_name doc);
    foreach my $item ( @prop_list )  {
        my $val = eval { $class->$item };
        $printed{$item} = 1;
        next unless defined $val;
        printf("    %16s  %s\n", $item, $val);
    }

    

    my @data_sources = $UR::Context::current->resolve_data_sources_for_class_meta_and_rule($class);
    { no warnings 'uninitialized';
      printf("    %16s  %s\n", 'data_source', join(',',map { $_ and $_->id } @data_sources));
    }
    
    delete @all_class_properties{(@prop_list, @CLASS_PROPERTIES_NOT_TO_PRINT, 'id_by','is','class_name','source','data_source_id')};
    foreach my $item ( sort keys %all_class_properties ) {
        next if $printed{$item}++;

        my $prop_meta = $class_meta->property_meta_for_name($item);
        next if $prop_meta->is_delegated;  # Not interested in those delegated properties

        my $val = eval { $class->$item };
        if ($item =~ /^is_/) {
            $val = ($val ? "TRUE" : "FALSE");
        }
        next unless defined $val;
        printf("    %16s  %s\n", $item, $val);
    }

    
    my %id_properties = map { $_ => 1 } $class->all_id_property_names;
    my %printed_properties;
    my @properties = 
        sort { 
            defined($id_properties{$a}) cmp defined($id_properties{$b})
            ||
            $a->property_name cmp $b->property_name 
        } 
        grep { ! $printed_properties{$_->property_name}++ }
        $class->all_property_metas;

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
