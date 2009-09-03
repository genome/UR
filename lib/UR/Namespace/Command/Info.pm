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

    my %viewers;
    foreach my $item ( @{$params->{' '}} ) {
        my @meta_objs = ();

        if ($item eq $namespace or $item =~ m/::/) {
            # Looks like a class name?  
            my $class_meta = eval { UR::Object::Type->get(class_name => $item)};
            push(@meta_objs, $class_meta) if $class_meta;

        } else {

            push @meta_objs, ( UR::DataSource::RDBMS::Table->get(table_name => $item, namespace => $namespace) );
            push @meta_objs, ( UR::DataSource::RDBMS::Table->get(table_name => uc($item), namespace => $namespace) );
            push @meta_objs, ( UR::DataSource::RDBMS::Table->get(table_name => lc($item), namespace => $namespace) );

            push @meta_objs, map { ( $_ and UR::DataSource::RDBMS::Table->get(table_name => $_->table_name, namespace => $namespace) ) }
                                 ( UR::DataSource::RDBMS::TableColumn->get(column_name => $item, namespace => $namespace),
                                   UR::DataSource::RDBMS::TableColumn->get(column_name => uc($item), namespace => $namespace),
                                   UR::DataSource::RDBMS::TableColumn->get(column_name => lc($item), namespace => $namespace)
                                 );

        }
    
        ## A property search requires loading all the classes first, at least until class
        ## metadata is in the meta DB
        # Something is making this die, so I'll comment it out for now
        #$namespace->get_material_class_names;
        #my @properties = UR::Object::Property->get(property_name => $item);
        #next unless @properties;
        #push @meta_objs, UR::Object::Type->get(class_name => [ map { $_->class_name }
        #                                                            @properties ]);

        foreach my $obj ( @meta_objs ) {
            next unless $obj;
            next if ($already_printed{$obj}++);

            $viewers{$obj->class} ||= UR::Object::Viewer->create_viewer(
                                          subject_class_name => $obj->class,
                                          perspective => 'default',
                                          toolkit => 'text',
                                       );
 

            my $viewer = $viewers{$obj->class};
            $viewer->set_subject($obj);
            $viewer->show();
            print "\n";
        }
   
    }
}

    
1;
