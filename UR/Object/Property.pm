package UR::Object::Property;

use warnings;
use strict;
use Lingua::EN::Inflect;

our $VERSION = '2.0';

=pod

UR::Object::Type->define(
    class_name => 'UR::Object::Property',
    english_name => 'entity type attribute',
    id_properties => [qw/type_name attribute_name/],
    properties => [
        attribute_name                   => { type => 'VARCHAR2', len => 64 },
        type_name                        => { type => 'VARCHAR2', len => 64 },
        class_name                       => { type => 'VARCHAR2', len => 64 },
        column_name                      => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        data_length                      => { type => 'VARCHAR2', len => 32, is_optional => 1 },
        default_value                    => { is_optional => 1 },
        data_type                        => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        doc                              => { type => 'VARCHAR2', len => 1000, is_optional => 1 },
        is_class_wide                    => { type => 'BOOL', len => undef },
        is_constant                      => { type => 'BOOL', len => undef },
        is_optional                      => { type => 'BOOL', len => undef },
        is_transient                     => { type => 'BOOL', len => undef },
        is_delegated                     => { type => 'BOOL', len => undef },
        is_calculated                    => { type => 'BOOL', len => undef },
        is_mutable                       => { type => 'BOOL', len => undef },
        is_numeric                       => { calculate_from => ['data_type'], },
        property_name                    => { type => 'VARCHAR2', len => 64 },
        property_type                    => { type => 'VARCHAR2', len => 64 },
        source                           => { type => 'VARCHAR2', len => 64 },
    ],
    unique_constraints => [
        { properties => [qw/property_name type_name/], sql => 'SUPER_FAKE_O4' },
    ],
);

=cut

# Implements the is_numeric calculated property - returns true if it's ok to use
# numeric comparisons (==, <, <=>, etc) on the property
our %NUMERIC_TYPES = (
        'INTEGER' => 1,
        'NUMBER'  => 1,
        'FLOAT'   => 1,
);
sub is_numeric {
    my $self = shift;

    unless (defined($self->{'_is_numeric'})) {
        my $type = uc($self->data_type);
        $self->{'_is_numeric'} = $NUMERIC_TYPES{$type} || 0;
    }
    return $self->{'_is_numeric'};
}    
        
        

sub create_object {
    my $class = shift;
    my ($bx,%extra) = $class->define_boolexpr(@_);
    my %params = ($bx->params_list,%extra);
    #print Data::Dumper::Dumper(\%params);
    #%params = $class->preprocess_params(@_);
   
=cut
 
    if ($params{attribute_name} and not $params{property_name}) {
        my $property_name = $params{attribute_name};
        $property_name =~ s/ /_/g;
        $params{property_name} = $property_name;
    }
    elsif ($params{property_name} and not $params{attribute_name}) {
        my $attribute_name = $params{property_name};
        $attribute_name =~ s/_/ /g;
        $params{attribute_name} = $attribute_name;
    }
    unless ($params{class_name} and $params{type_name}) {   
        my $class_obj;
        if ($params{type_name}) {
            $class_obj = UR::Object::Type->is_loaded(type_name => $params{type_name});
            $params{class_name} = $class_obj->class_name;
        } 
        elsif ($params{class_name}) {
            $class_obj = UR::Object::Type->is_loaded(class_name => $params{class_name});
            $params{type_name} = $class_obj->type_name;
        } 
    }

=cut
    
    my ($singular_name,$plural_name);
    if ($params{is_many}) {
        require Lingua::EN::Inflect;
        $plural_name = $params{property_name};
        $singular_name = Lingua::EN::Inflect::PL_V($plural_name);
    }
    else {
        $singular_name = $params{property_name};
        $plural_name = Lingua::EN::Inflect::PL($singular_name);
    }

    return $class->SUPER::create_object(plural_name => $plural_name, singular_name => $singular_name, %params);
}


# Returns the table and column for this property.
# If this particular property doesn't have a column_name, and it
# overrides a property defined on a parent class, then walk up the
# inheritance and find the right one
sub table_and_column_name_for_property {
    my $self = shift;

    # Shortcut - this property has a column_name, so the class should have the right
    # table_name
    if ($self->column_name) {
        return ($self->class_name->__meta__->table_name, $self->column_name);
    }

    my $property_name = $self->property_name;
    my @class_metas = $self->class_meta->parent_class_metas;

    my %seen;
    while (@class_metas) {
        my $class_meta = shift @class_metas;
        next if ($seen{$class_meta}++);

        my $p = $class_meta->property_meta_for_name($property_name);
        next unless $p;

        if ($p->column_name && $class_meta->table_name) {
            return ($class_meta->table_name, $p->column_name);
        }

        push @class_metas, $class_meta->parent_class_metas;
    }

    # This property has no column anywhere in the class' inheritance
    return;
}


# For via/to delegated properties, return the property meta in the same
# class this property delegates through
sub via_property_meta {
    my $self = shift;

    return unless ($self->is_delegated and $self->via);
    my $class_meta = $self->class_meta;
    return $class_meta->property_meta_for_name($self->via);
}

# For via/to delegated properties, return the property meta on the foreign
# class that this property delegates to
sub to_property_meta {
    my $self = shift;

    return unless ($self->is_delegated && $self->to);

    my $via_meta = $self->via_property_meta();
    return unless $via_meta;

    my $remote_class = $via_meta->data_type;
    my $remote_class_meta = UR::Object::Type->get($remote_class);
    return unless $remote_class_meta;

    return $remote_class_meta->property_meta_for_name($self->to);
}


sub get_property_name_pairs_for_join {
    my ($self) = @_;
    my @linkage = $self->_get_direct_join_linkage();
    unless (@linkage) {
        die "No linkage for property " . $self->id;
    }
    if ($self->class_name eq $linkage[0]->class_name) {
        return map { [ $_->property_name => $_->r_property_name ] } @linkage;
    }
    else {
        return map { [ $_->r_property_name => $_->property_name ] } @linkage;
    }    
}

sub _get_direct_join_linkage {
    my ($self) = @_;
    my @obj;
    if (my $id_by = $self->id_by) {
        @obj = 
            sort { $a->rank <=> $b->rank } 
            UR::Object::Reference::Property->get(
                tha_id => $self->class_name . "::" . $self->property_name
            );        

    }
    elsif (my $reverse_as = $self->reverse_as) {
        my $r_class_name = $self->data_type;
        @obj = 
            $r_class_name->__meta__->property_meta_for_name($reverse_as)->_get_direct_join_linkage();
    }
    return @obj;
}

my @old = qw/source_class source_class_meta source_property_names foreign_class foreign_class_meta foreign_property_names/;
my @new = qw/foreign_class foreign_class_meta foreign_property_names source_class source_class_meta source_property_names/;
sub _get_joins {
    my $self = shift;
    unless ($self->{_get_joins}) {
        my $class_meta = UR::Object::Type->get(class_name => $self->class_name);
        my @joins;
        
        if (my $via = $self->via) {
            my $via_meta = $class_meta->property_meta_for_name($via);
            unless ($via_meta) {
                my $property_name = $self->property_name;
                my $class_name = $self->class_name;
                Carp::croak "Can't resolve property $property_name of $class_name: No via meta for '$via'?";
            }
            unless ($via_meta->data_type) {
                my $property_name = $self->property_name;
                my $class_name = $self->class_name;
                Carp::croak "Can't resolve property $property_name of $class_name: No data type for '$via'?";
            }
            push @joins, $via_meta->_get_joins();
            
            my $to = $self->to;
            unless ($to) {
                $to = $self->property_name;
            }
            if (my $where = $self->where) {
                if ($where->[1] eq 'name') {
                    @$where = reverse @$where;
                }            
                my $join = pop @joins;
                #my $where_rule = $join->{foreign_class}->define_boolexpr(@$where);                
                my $where_rule = UR::BoolExpr->resolve_for_class_and_params($join->{foreign_class}, @$where);                
                my $id = $join->{id};
                $id .= ' ' . $where_rule->id;
                push @joins, { %$join, id => $id, where => $where };
            }
            unless ($to eq 'self') {
                my $to_meta = $via_meta->data_type->__meta__->property_meta_for_name($to);
                unless ($to_meta) {
                    my $property_name = $self->property_name;
                    my $class_name = $self->class_name;
                    Carp::croak "Can't resolve property $property_name of $class_name: No '$to' property found on " . $via_meta->data_type;
                }
                push @joins, $to_meta->_get_joins();
            }
        }
        else {
            my $source_class = $class_meta->class_name;            
            my $foreign_class = $self->data_type;
            my $where = $self->where;
            if (defined($where) and defined($where->[1]) and $where->[1] eq 'name') {
                @$where = reverse @$where;
            }
            
            if (defined($foreign_class) and $foreign_class->can('get')) {
                #print "class $foreign_class, joining...\n";
                my $foreign_class_meta = $foreign_class->__meta__;
                my $property_name = $self->property_name;
                my $id = $source_class . '::' . $property_name;
                if ($where) {
                    #my $where_rule = $foreign_class->define_boolexpr(@$where);
                    my $where_rule = UR::BoolExpr->resolve_for_class_and_params($foreign_class, @$where);
                    $id .= ' ' . $where_rule->id;
                }
                if (my $id_by = $self->id_by) { 
                    my(@source_property_names, @foreign_property_names);
                    # This ensures the linking properties will be in the right order
                    foreach my $ref_property ( $self->id_by_property_links ) {
                        push @source_property_names, $ref_property->property_name;
                        push @foreign_property_names, $ref_property->r_property_name;
                    }
               
                    if (ref($id_by) eq 'ARRAY') {
                        # satisfying the id_by requires joins of its own
                        foreach my $id_by_property_name ( @$id_by ) {
                            my $id_by_property = $class_meta->property_meta_for_name($id_by_property_name);
                            next unless ($id_by_property and $id_by_property->is_delegated);
                           
                            push @joins, $id_by_property->_get_joins();
                        }
                    }
                    
                    push @joins, {
                        id => $id,
                        source_class => $source_class,
                        source_class_meta => $class_meta,
                        source_property_names => \@source_property_names,
                        foreign_class => $foreign_class,
                        foreign_class_meta => $foreign_class_meta,
                        foreign_property_names => \@foreign_property_names,
                        where => $where,
                    }
                }
                elsif (my $reverse_as = $self->reverse_as) { 
                    my $foreign_class = $self->data_type;
                    my $foreign_class_meta = $foreign_class->__meta__;
                    my $foreign_property_via = $foreign_class_meta->property_meta_for_name($reverse_as);
                    unless ($foreign_property_via) {
                        Carp::confess("No property '$reverse_as' in class $foreign_class, needed to resolve property '" .
                                      $self->property_name . "' of class " . $self->class_name);
                    }
                    @joins = reverse $foreign_property_via->_get_joins();
                    for (@joins) { 
                        @$_{@new} = @$_{@old};
                    }

                } else {
                    $self->error_message("Property $id has no 'id_by' or 'reverse_as' property metadata");
                }
            }
            else {
                #print "   value $foreign_class ..nojoin\n";
            }
        }
        
        $self->{_get_joins} = \@joins;
        return @joins;        
        
    }
    return @{ $self->{_get_joins} };
}


sub label_text 
{
    # The name of the property in friendly terms.
    my ($self,$obj) = @_;
    my $attribute_name = $self->attribute_name;
    my @words = App::Vocabulary->filter_vocabulary(map { ucfirst(lc($_)) } split(/\s+/,$attribute_name));
    my $label = join(" ", @words);
    return $label;
}

# A mapping of Oracle data types to generic types.
our %generic_data_type_for_vendor_data_type =
(
    'CHAR'        => 'Text',
    'VARCHAR2'    => 'Text',
    'NCHAR'       => 'Text',
    'NVARCHAR2'   => 'Text',
    'ROWID'       => 'Text',
    'LONG'        => 'Text',
    'LONGRAW'     => 'Text',
    
    'FLOAT'       => 'Float',
    
    'NUMBER'      => 'Float',  # not true, but sometimes true
    
    'DATE'        => 'DateTime',
    'TIMESTAMP'   => 'DateTime',
 
    'BLOB'        => 'Ugly',
    'CLOB'        => 'Ugly',
    'NCLOB'       => 'Ugly',
    'RAW'         => 'Ugly',
    'UNDEFINED'   => 'Ugly',
);

sub generic_data_type {
    no warnings;
    return $generic_data_type_for_vendor_data_type{$_[0]->{data_type}};
}

sub is_indirect {
    my $self = shift;

    return ($self->is_delegated || $self->is_calculated || $self->is_legacy_eav);
}



sub id_by_property_links {
    my $self = shift;
    my @r = sort { $a->rank <=> $b->rank } UR::Object::Reference::Property->get(tha_id => $self->class_name . "::" . $self->property_name);
    return @r;
}

sub r_id_by_property_links {
    my $self = shift;
    my $r_id_by = $self->reverse_as;
    my $r_class_name = $self->data_type;
    my @r = sort { $a->rank <=> $b->rank } UR::Object::Reference::Property->get(tha_id => $self->class_name . "::" . $self->property_name);
    return @r;
}


1;
