package UR::Namespace::Command::Info;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command',
);


sub help_brief {
    "Outputs description(s) of UR entities such as classes and tables to stdout";
}

sub is_sub_command_delegator { 0;}


sub execute {
my($self, $params) = @_;

    $DB::single=1;
    my $namespace = $self->namespace_name;
    # FIXME why dosen't require work here?
    eval "use  $namespace";
    if ($@) {
        $self->error_message("Failed to load module for $namespace: $@");
        return;
    }

    # Loop through each command line parameter and see what kind of thing it is
    # create a viewer and display it
    my @class_aspects = qw( );
    my @table_aspects = qw( );
    my %already_printed;
    my @viewers;
    foreach my $item ( @{$params->{' '}} ) {
        my @meta_objs = ();

        if ($item eq $namespace or $item =~ m/::/) {
            # Looks like a class name?  
            push @meta_objs, eval { UR::Object::Type->get(class_name => $item)};
        }

        push @meta_objs, UR::DataSource::RDBMS::Table->get(table_name => $item);
        push @meta_objs, UR::DataSource::RDBMS::Table->get(table_name => uc($item));
        push @meta_objs, UR::DataSource::RDBMS::Table->get(table_name => lc($item));

        push @meta_objs, map { UR::DataSource::RDBMS::Table->get(table_name => $_) }
                             ( UR::DataSource::RDBMS::TableColumn->get(column_name => $item),
                               UR::DataSource::RDBMS::TableColumn->get(column_name => uc($item)),
                               UR::DataSource::RDBMS::TableColumn->get(column_name => lc($item)));
    
        ## A property search requires loading all the classes first, at least until class
        ## metadata is in the meta DB
        # Something is making this die, so I'll comment it out for now
        #$namespace->get_material_class_names;
        #my @properties = UR::Object::Property->get(property_name => $item);
        #next unless @properties;
        #push @meta_objs, UR::Object::Type->get(class_name => [ map { $_->class_name }
        #                                                            @properties ]);
        
        foreach my $obj ( @meta_objs ) {
            next if ($already_printed{$obj}++);

            my $viewer = $obj->create_viewer(toolkit => 'text');
            print $viewer->show();
            print "\n\n";
        }
   
    }
}

    

sub old_for_each_class_object {
    my $self = shift;
    my $class = shift;

    print $class->class_name,"  Table ",$class->table_name,"\n";
    
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
        next unless defined $val;
        printf("    %16s  %s\n", $item, $val);
    }

    
    my @properties = sort { $a->property_name cmp $b->property_name } $class->get_all_property_objects;
    my %id_properties = map { $_ => 1 } $class->all_id_property_names;
    print "\nProperties\n" if (@properties);
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
    print "\nRelationships\n" if (@relationships);
    foreach my $rel ( @relationships ) {
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
}

1;
