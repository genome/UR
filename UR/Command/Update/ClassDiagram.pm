
package UR::Command::Update::ClassDiagram;



use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Command',
    has => [ 
        data_source => {type => 'String', doc => 'Which datasource to use', is_optional => 1},
        depth => { type => 'Integer', doc => 'Max distance of related classes to include.  Default is 1.  0 means show only the named class(es), -1 means to include everything', is_optional => 1},
        file => { type => 'String', doc => 'Pathname of the Umlet (.uxf) file' },
        show_attributes => { type => 'Boolean', is_optional => 1, default => 1, doc => 'Include class attributes in the diagram' },
        show_methods => { type => 'Boolean', is_optional => 1, default => 0, doc => 'Include methods in the diagram (not implemented yet' },
    ],
);


sub help_brief {
    "Update an Umlet diagram based on the current class definitions"
}

sub help_detail {
    return <<EOS;
Creates a new Umlet diagram, or updates an existing diagram.  Bare arguments
are taken as class names to include in the diagram.  Other classes may be
included in the diagram based on their distance from the names classes
and the --depth parameter.

If an existing file is being updated, the position of existing elements 
will not change.

EOS
}

# The max X coord to use when placing boxes.  After this, move down a line and go back to the left
use constant MAX_X_AUTO_POSITION => 800;

sub execute {
    my $self = shift;
    my $params = shift;
    
$DB::single=1;
    my $namespace = $self->namespace_name;
    eval "use $namespace";
    if ($@) {
        $self->error_message("Failed to load module for $namespace: $@");
        return;
    }

    my @initial_name_list = @{$params->{' '}};

    my $diagram;
    if (-f $params->{'file'}) {
        $params->{'depth'} = 0 unless (exists $params->{'depth'});  # Default is just update what's there
        $diagram = UR::Object::Umlet::Diagram->create_from_file($params->{'file'});
        push @initial_name_list, map { $_->subject_id } UR::Object::Umlet::Class->get(diagram_name => $diagram->name);
    } else {
        $params->{'depth'} = 1 unless exists($params->{'depth'});
        $diagram = UR::Object::Umlet::Diagram->create(name => $params->{'file'});
    }

    # FIXME this can get removed when attribute defaults work correctly
    unless (exists $params->{'show_attributes'}) {
        $self->show_attributes(1);
    }
        
    my @involved_classes;
    foreach my $class_name ( @initial_name_list ) {
        push @involved_classes, UR::Object::Type->get(class_name => $class_name);
    }

    push @involved_classes ,$self->_get_related_items( names => \@initial_name_list,
                                                       depth => $params->{'depth'},
                                                       item_class => 'UR::Object::Type',
                                                       item_param => 'class_name',
                                                       related_class => 'UR::Object::Reference',
                                                       related_param => 'r_class_name',
                                                     );
    push @involved_classes, $self->_get_related_items( names => \@initial_name_list,
                                                       depth => $params->{'depth'},
                                                       item_class => 'UR::Object::Type',
                                                       item_param => 'class_name',
                                                       related_class => 'UR::Object::Inheritance',
                                                       related_param => 'parent_class_name',
                                                     );
    my %involved_class_names = map { $_->class_name => 1 } @involved_classes;

    # The initial placement, and how much to move over for the next box
    my($x_coord, $y_coord, $x_inc, $y_inc) = (20,20,40,40);
    my @objs = sort { $b->y <=> $a->y or $b->x <=> $a->x } UR::Object::Umlet::Class->get();
    if (@objs) {
        my $maxobj = $objs[0];
        $x_coord = $maxobj->x + $maxobj->width + $x_inc;
        $y_coord = $maxobj->y + $maxobj->height + $y_inc;
    }
    

    # First, place all the classes
    my @all_boxes = UR::Object::Umlet::Class->get( diagram_name => $diagram->name );
    foreach my $class ( @involved_classes ) {
        my $umlet_class = UR::Object::Umlet::Class->get(diagram_name => $diagram->name,
                                                        subject_id => $class->class_name);
        my $created = 0;
        unless ($umlet_class) {
            $created = 1;
            $umlet_class = UR::Object::Umlet::Class->create( diagram_name => $diagram->name,
                                                             subject_id => $class->class_name,
                                                             label => $class->class_name,
                                                             x => $x_coord,
                                                             y => $y_coord,
                                                           );
             # add the attributes
             if ($self->show_attributes) {
                my $attributes = $umlet_class->attributes || [];
                my %attributes_already_in_diagram = map { $_->{'name'} => 1 } @{ $attributes };
                my %id_properties = map { $_ => 1 } $class->id_property_names;
    
                my $line_count = scalar @$attributes;
                foreach my $property_name ( $class->instance_property_names ) {
                    next if $attributes_already_in_diagram{$property_name};
                    $line_count++;
                    my $property = UR::Object::Property->get(class_name => $class->class_name, property_name => $property_name);
                    push @$attributes, { is_id => $id_properties{$property_name} ? '+' : ' ',
                                         name => $property_name,
                                         type => $property->data_type,
                                         line => $line_count,
                                       };
                }
                $umlet_class->attributes($attributes);
            }

            if ($self->show_methods) {
                # Not implemented yet
                # Use the same module the schemabrowser uses to get that info
            }

            # Make sure this box dosen't overlap other boxes
            while(my $overlapped = $umlet_class->is_overlapping(@all_boxes) ) {
                if ($umlet_class->x > MAX_X_AUTO_POSITION) {
                    $umlet_class->x(20);
                    $umlet_class->y( $umlet_class->y + $y_inc);
                } else {
                    $umlet_class->x( $overlapped->x + $overlapped->width + $x_inc );
                }
            }
                                                            
            push @all_boxes, $umlet_class;
        }

        if ($created) {
            $x_coord = $umlet_class->x + $umlet_class->width + $x_inc;
            if ($x_coord > MAX_X_AUTO_POSITION) {
                $x_coord = 20;
                $y_coord += $y_inc;
            }
        }
    }

    # Next, connect the classes together
    foreach my $class ( @involved_classes ) {
        foreach my $reference ( UR::Object::Reference->get(class_name => $class->class_name) )  {

            next unless ($involved_class_names{$reference->r_class_name});

            # FIXME There seems to be a bug in get() here.  It's returning all the ref properties with that
            # class, and not just the single one with that tha_id
            my @ref_property = UR::Object::Reference::Property->get(class_name => $class->class_name,
                                                                     tha_id => $reference->tha_id);
            my($ref_property) = grep { $_->tha_id eq $reference->tha_id } @ref_property;

            my $umlet_relation = UR::Object::Umlet::Relation->get( diagram_name => $diagram->name,
                                                                   from_entity_name => $reference->class_name,
                                                                   to_entity_name => $reference->r_class_name,
                                                                   from_attribute_name => $ref_property->property_name,
                                                                   to_attribute_name => $ref_property->r_property_name,
                                                                 );
            unless ($umlet_relation) {                             
                $umlet_relation = UR::Object::Umlet::Relation->create( diagram_name => $diagram->name,
                                                                       relation_type => '&lt;-',
                                                                       from_entity_name => $reference->class_name,
                                                                       to_entity_name => $reference->r_class_name,
                                                                       from_attribute_name => $ref_property->property_name,
                                                                       to_attribute_name => $ref_property->r_property_name,
                                                                     );
                 $umlet_relation->connect_entity_attributes();
            }

        }

        foreach my $inh ( UR::Object::Inheritance->get(class_name => $class->class_name) ) {
            next unless ($involved_class_names{$inh->parent_class_name});

            my $umlet_relation = UR::Object::Umlet::Relation->get( diagram_name => $diagram->name,
                                                                   from_entity_name => $class->class_name,
                                                                   to_entity_name => $inh->parent_class_name,
                                                                 );
            unless ($umlet_relation) {
                $umlet_relation = UR::Object::Umlet::Relation->create( diagram_name => $diagram->name,
                                                                       relation_type => '&lt;&lt;-',
                                                                       from_entity_name => $class->class_name,
                                                                       to_entity_name => $inh->parent_class_name,
                                                                     );
                 $umlet_relation->connect_entities();
            }
        }
    }

    $diagram->save_to_file($params->{'file'});

    1;
}



sub _get_related_items {
my($self, %params) = @_;

    return unless (@{$params{'names'}});
    return unless $params{'depth'};

    my $item_class = $params{'item_class'};
    my $item_param = $params{'item_param'};

    my $related_class = $params{'related_class'};
    my $related_param = $params{'related_param'};

    # Get everything linked to the named things
    my @related_names = map { $_->$related_param } $related_class->get($item_param => $params{'names'});
    push @related_names, map { $_->$item_param } $related_class->get($related_param => $params{'names'});
    return unless @related_names;

    my @objs = $item_class->get($item_param => \@related_names);

    # make a recursive call to get the related objects by name
    return ( @objs, $self->_get_related_items( %params, names => \@related_names, depth => --$params{'depth'}) );
}
    


1;

