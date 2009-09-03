package UR::Object::Property;

use warnings;
use strict;

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
        property_name                    => { type => 'VARCHAR2', len => 64 },
        property_type                    => { type => 'VARCHAR2', len => 64 },
        source                           => { type => 'VARCHAR2', len => 64 },
    ],
    unique_constraints => [
        { properties => [qw/property_name type_name/], sql => 'SUPER_FAKE_O4' },
    ],
);

=cut

sub is_aggregate {
    my $self = shift;
    # TODO: calclulated properties, might auto-aggregate.  By default nothing does. 
    return;
}

sub create_object {
    my $class = shift;
    my %params = $class->preprocess_params(@_);
    #print Data::Dumper::Dumper(\%params);
    #$DB::single = 1;
    #%params = $class->preprocess_params(@_);
    
    
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
    
    return $class->SUPER::create_object(%params);
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
    elsif (my $reverse_id_by = $self->reverse_id_by) {
        my $r_class_name = $self->data_type;
        @obj = 
            $r_class_name->get_class_object->get_property_meta_by_name($reverse_id_by)->_get_direct_join_linkage();
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
            my $via_meta = $class_meta->get_property_meta_by_name($via);
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
            my $to_meta = $via_meta->data_type->get_class_object->get_property_meta_by_name($to);
            unless ($to_meta) {
                my $property_name = $self->property_name;
                my $class_name = $self->class_name;
                Carp::croak "Can't resolve property $property_name of $class_name: No '$to' property found on " . $via_meta->data_type;
            }
            push @joins, $to_meta->_get_joins();
        }
        else {
            my $source_class = $class_meta->class_name;            
            my $foreign_class = $self->data_type;
            if (defined($foreign_class) and $foreign_class->can('get')) {
                #print "class $foreign_class, joining...\n";
                my $foreign_class_meta = $foreign_class->get_class_object;
                my $property_name = $self->property_name;
                my $id = $source_class . '::' . $property_name;
                if (my $id_by = $self->id_by) { 
                    push @joins, {
                        id => $id,
                        source_class => $source_class,
                        source_class_meta => $class_meta,
                        source_property_names => [ @$id_by ],
                        foreign_class => $foreign_class,
                        foreign_class_meta => $foreign_class_meta,
                        foreign_property_names => [ $foreign_class_meta->id_property_names ],
                    }
                }
                elsif (my $reverse_id_by = $self->reverse_id_by) { 
                    my $foreign_class = $self->data_type;
                    my $foreign_class_meta = $foreign_class->get_class_object;
                    my $foreign_property_via = $foreign_class_meta->get_property_meta_by_name($reverse_id_by);
                    @joins = reverse $foreign_property_via->_get_joins();
                    for (@joins) { 
                        @$_{@new} = @$_{@old};
                    }
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


sub ref_type_names {
    my $self = shift;
    unless ($self->{ref_type_names})
    { 
        my $data_type = $self->data_type;
        my $type_name = $self->type_name;
        my $attribute_name = $self->attribute_name;
        my @taha = 
           map { UR::Object::Reference::Property->get(tha_id=>$_->id, attribute_name=>$attribute_name) } 
            UR::Object::Reference->get(type_name => $type_name);
        my @ref_type_names;    
        for my $taha (@taha)
        {
            my $tha = UR::Object::Reference->get($taha->tha_id);
            push @ref_type_names, $tha->r_type_name;        
        } 
        $self->{ref_type_names} = \@ref_type_names;
    }
    return @{ $self->{ref_type_names} };
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

# A List of Oracle Column Types we can't query by
# LONG and LONGRAW are definitely no good
our %unqueryable_data_types=('LONG'    => 1,
                             'LONGRAW' => 1,
# Plus, add anything above that is defined as 'Ugly'
                             map {($_ => 1)} 
                             grep {$generic_data_type_for_vendor_data_type{$_} eq 'Ugly'} 
                             keys %generic_data_type_for_vendor_data_type);
sub is_queryable {
    return unless ($_[0]->data_type);
    return !exists($unqueryable_data_types{$_[0]->data_type});
}


sub is_indirect {
    my $self = shift;

    return ($self->is_delegated || $self->is_calculated || $self->is_legacy_eav);
}



#
# OBSOLETE
#

# legacy accessors
sub description { shift->doc(@_) }

# The legacy name is 'nullable', the new is 'is_optional'
sub nullable { # Carp::carp(q(Legacy call to 'nullable()' should change to 'is_optional'));
               shift->is_optional(@_)
             }

sub id_by_property_links {
    my $self = shift;
    my @r = sort { $a->rank <=> $b->rank } UR::Object::Reference::Property->get(tha_id => $self->class_name . "::" . $self->property_name);
    return @r;
}

sub r_id_by_property_links {
    my $self = shift;
    my $r_id_by = $self->reverse_id_by;
    my $r_class_name = $self->data_type;
    my @r = sort { $a->rank <=> $b->rank } UR::Object::Reference::Property->get(tha_id => $self->class_name . "::" . $self->property_name);
    return @r;
}


sub id_by_property_names {
    my $self = shift;
    my @r = $self->id_by_property_links();
    return map { $_->property_name } @r;
}

sub r_id_by_property_names {
    my $self = shift;
    my @r = $self->id_by_property_links();
    return map { $_->r_property_name } @r;
}

1;
