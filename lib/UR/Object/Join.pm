package UR::Object::Join;
use strict;
use warnings;
use UR;
our $VERSION = "0.38"; # UR $VERSION;

our @CARP_NOT = qw( UR::Object::Property );

class UR::Object::Join {
    #is => 'UR::Value',
    id_by => [
        id                      => { is => 'Text' },
    ],
    has_optional_transient => [
        source_class            => { is => 'Text' },
        source_property_names   => { is => 'Text' },
        
        foreign_class           => { is => 'Text' },
        foreign_property_names  => { is => 'Text' },
        
        source_name_for_foreign => { is => 'Text' },
        foreign_name_for_source => { is => 'Text' },
        
        is_optional             => { is => 'Boolean' }, 

        is_many                 => { is => 'Boolean' },

        sub_group_label         => { is => 'Text' },

        where                   => { is => 'Text' },
    ],
    doc => "join metadata used internally by the ::QueryBuilder"
};

our %resolve_chain;
sub resolve_chain {
    my ($class, $class_name, $property_chain, $join_label) = @_;

    $join_label ||= $property_chain;

    my $join_chain = 
        $resolve_chain{$class_name}{$join_label}{$property_chain}
            ||= do {
                my $class_meta = $class_name->__meta__;
                my @pmeta = $class_meta->property_meta_for_name($property_chain);
                my @joins;
                for my $pmeta (@pmeta) {
                    push @joins, $class->_resolve_chain_for_property_meta($pmeta,$join_label);
                }
                \@joins;
            };

    return @$join_chain;
}

sub _resolve_chain_for_property_meta {
    my ($class, $pmeta, $join_label) = @_;  
    if ($pmeta->via or $pmeta->to) {
        return $class->_resolve_via_to($pmeta,$join_label);
    }
    else {
        my $foreign_class = $pmeta->_data_type_as_class_name;
        unless (defined($foreign_class) and $foreign_class->can('get'))  {
            return;
        }
        if ($pmeta->id_by or $foreign_class->isa("UR::Value")) {
            return $class->_resolve_forward($pmeta, $join_label);
        }
        elsif (my $reverse_as = $pmeta->reverse_as) { 
            return $class->_resolve_reverse($pmeta,$join_label);
        }
        else {
            # TODO: handle hard-references to objects here maybe?
            $pmeta->error_message("Property " . $pmeta->id . " has no 'id_by' or 'reverse_as' property metadata");
            return;
        }
    }
}

sub _get_or_define {
    my $class = shift;
    my %p = @_;
    my $id = delete $p{id};
    delete $p{__get_serial};
    delete $p{db_committed};
    delete $p{_change_count};
    delete $p{__defined};
    my $self = $class->get(id => $id);
    unless ($self) {
        $self = $class->__define__($id);
        for my $k (keys %p) {
            $self->$k($p{$k});
            no warnings;
            unless ($self->{$k} eq $p{$k}) {
                Carp::confess(Data::Dumper::Dumper($self, \%p));
            }   
        }
    }
    unless ($self) {
        Carp::confess("Failed to create join???");
    }
    return $self;
}

sub _resolve_via_to {
    my ($class, $pmeta,$join_label) = @_;

    my $class_name = $pmeta->class_name;
    my $class_meta = UR::Object::Type->get(class_name => $class_name);

    my @joins;
    my $via = $pmeta->via;

    my $to = $pmeta->to;    
    if ($via and not $to) {
        $to = $pmeta->property_name;
    }

    my $via_meta;
    if ($via) {
        $via_meta = $class_meta->property_meta_for_name($via);
        unless ($via_meta) {
            return if $class_name->can($via);  # It's via a method, not an actual property

            my $property_name = $pmeta->property_name;
            my $class_name = $pmeta->class_name;
            Carp::croak "Can't resolve joins for property '$property_name' of $class_name: No property metadata for via property '$via'";
        }

        if ($via_meta->to and ($via_meta->to eq '-filter')) {
            return $class->resolve_chain($via_meta->class_name, $via_meta->property_name, $join_label);
        }

        unless ($via_meta->data_type) {
            my $property_name = $pmeta->property_name;
            my $class_name = $pmeta->class_name;
            Carp::croak "Can't resolve joins for property '$property_name' of $class_name: No data type for via property '$via'";
        }
        push @joins, $class->resolve_chain($via_meta->class_name, $via_meta->property_name, $join_label);
        
        if (my $where = $pmeta->where) {
            my $join = pop @joins;
            unless ($join and $join->{foreign_class}) {
                my $property_name = $pmeta->property_name;
                my $class_name = $pmeta->class_name;
                Carp::croak("Can't resolve joins for property '$property_name' of $class_name: Couldn't determine foreign class for via property '$via'\n"
                            . "join data so far: ".  Data::Dumper::Dumper($join, \@joins));
            }
            my $where_rule = UR::BoolExpr->resolve($join->{foreign_class}, @$where);                
            my $id = $join->{id};
            $id .= ' ' . $where_rule->id . ":$join_label";
            my %join_data = %$join;
            push @joins, $class->_get_or_define(%join_data, id => $id, where => $where, sub_group_label => $pmeta->property_name);
        }
    }
    else {
        $via_meta = $pmeta;
    }

    if ($to and $to ne '__self__' and $to ne '-filter') {
        my $to_class_meta = eval { $via_meta->data_type->__meta__ };
        unless ($to_class_meta) {
            Carp::croak("Can't get class metadata for " . $via_meta->data_type
                        . " while resolving property '" . $pmeta->property_name . "' in class " . $pmeta->class_name . "\n"
                        . "Is the data_type for property '" . $via_meta->property_name . "' in class "
                        . $via_meta->class_name . " correct?");
        }

        my $to_meta = $to_class_meta->property_meta_for_name($to);
        unless ($to_meta) {
            my $property_name = $pmeta->property_name;
            my $class_name = $pmeta->class_name;
            Carp::croak "Can't resolve property '$property_name' of $class_name: No '$to' property found on " . $via_meta->data_type;
        }

        push @joins, $class->resolve_chain($to_meta->class_name, $to_meta->property_name, $join_label);
    }
    
    return @joins;
}

# code below uses these to convert objects using hash slices
my @old = qw/source_class source_property_names foreign_class foreign_property_names source_name_for_foreign foreign_name_for_source is_optional is_many sub_group_label/;
my @new = qw/foreign_class foreign_property_names source_class source_property_names foreign_name_for_source source_name_for_foreign is_optional is_many sub_group_label/;

sub _resolve_forward {
    my ($class, $pmeta, $join_label) = @_;

    my $foreign_class = $pmeta->_data_type_as_class_name;
    unless (defined($foreign_class) and $foreign_class->can('get'))  {
        #Carp::cluck("No metadata?!");
        return;
    }

    my $source_class = $pmeta->class_name;            
    my $class_meta = UR::Object::Type->get(class_name => $pmeta->class_name);
    my @joins;
    my $where = $pmeta->where;
    my $foreign_class_meta = $foreign_class->__meta__;
    my $property_name = $pmeta->property_name;

    my $id = $source_class . '::' . $property_name;
    if ($where) {
        my $where_rule = UR::BoolExpr->resolve($foreign_class, @$where);
        $id .= ' ' . $where_rule->id;
    }

    #####
    
    # direct reference (or primitive, which is a direct ref to a value obj)
    my (@source_property_names, @foreign_property_names);
    my ($source_name_for_foreign, $foreign_name_for_source);

    if ($foreign_class->isa("UR::Value")) {
        if (my $id_by = $pmeta->id_by) {
            my @id_by = ref($id_by) eq 'ARRAY' ? @$id_by : ($id_by);
            foreach my $id_by_name ( @id_by ) {
                my $id_by_property = $class_meta->property_meta_for_name($id_by_name);
                push @joins, $class->resolve_chain($id_by_property->class_name, $id_by_property->property_name, $join_label);
            }
        }

        @source_property_names = ($property_name);
        @foreign_property_names = ('id');

        $source_name_for_foreign = ($property_name);
    }
    elsif (my $id_by = $pmeta->id_by) { 
        my @pairs = $pmeta->get_property_name_pairs_for_join;
        @source_property_names  = map { $_->[0] } @pairs;
        @foreign_property_names = map { $_->[1] } @pairs;

        if (ref($id_by) eq 'ARRAY') {
            # satisfying the id_by requires joins of its own
            # sms: why is this only done on multi-value fks?
            foreach my $id_by_property_name ( @$id_by ) {
                my $id_by_property = $class_meta->property_meta_for_name($id_by_property_name);
                next unless ($id_by_property and $id_by_property->is_delegated);
            
                push @joins, $class->resolve_chain($id_by_property->class_name, $id_by_property->property_name, $join_label);
                $source_class = $joins[-1]->{'foreign_class'};
                @source_property_names = @{$joins[-1]->{'foreign_property_names'}};
            }
        }

        $source_name_for_foreign = $pmeta->property_name;
        my @reverse = $foreign_class_meta->properties(reverse_as => $source_name_for_foreign, data_type => $pmeta->class_name);
        my $reverse;
        if (@reverse > 1) {
            my @reduced = grep { not $_->where } @reverse;
            if (@reduced != 1) {
                Carp::confess("Ambiguous results finding reversal for $property_name!" . Data::Dumper::Dumper(\@reverse));
            }
            $reverse = $reduced[0];
        }
        else {
            $reverse = $reverse[0];
        }
        if ($reverse) {
            $foreign_name_for_source = $reverse->property_name;
        }
    }

    # the foreign class might NOT have a reverse_as, but
    # this records what to reverse in this case.
    $foreign_name_for_source ||= '<' . $source_class . '::' . $source_name_for_foreign;

    $id .= ":$join_label";

    push @joins, $class->_get_or_define( 
                    id => $id,

                    source_class => $source_class,
                    source_property_names => \@source_property_names,
                    
                    foreign_class => $foreign_class,
                    foreign_property_names => \@foreign_property_names,
                    
                    source_name_for_foreign => $source_name_for_foreign,
                    foreign_name_for_source => $foreign_name_for_source,
                    
                    is_optional => ($pmeta->is_optional or $pmeta->is_many),

                    is_many => $pmeta->is_many,

                    where => $where,
                );

    return @joins;
}

sub _resolve_reverse {
    my ($class, $pmeta,$join_label) = @_;

    my $foreign_class = $pmeta->_data_type_as_class_name;

    unless (defined($foreign_class) and $foreign_class->can('get'))  {
        #Carp::cluck("No metadata?!");
        return;
    }

    my $source_class = $pmeta->class_name;            
    my $class_meta = UR::Object::Type->get(class_name => $pmeta->class_name);
    my @joins;
    my $where = $pmeta->where;
    my $property_name = $pmeta->property_name;

    my $id = $source_class . '::' . $property_name;
    if ($where) {
        my $where_rule = UR::BoolExpr->resolve($foreign_class, @$where);
        $id .= ' ' . $where_rule->id;
    }

    #####
    
    my $reverse_as = $pmeta->reverse_as;

    my $foreign_class_meta = $foreign_class->__meta__;
    my $foreign_property_via = $foreign_class_meta->property_meta_for_name($reverse_as);
    unless ($foreign_property_via) {
        Carp::confess("No property '$reverse_as' in class $foreign_class, needed to resolve property '" .
                        $pmeta->property_name . "' of class " . $pmeta->class_name);
    }

    my @join_data = map { { %$_ } } reverse $class->resolve_chain($foreign_property_via->class_name, $foreign_property_via->property_name, $join_label);
    my $prev_where = $where;
    for (@join_data) { 
        @$_{@new} = @$_{@old};

        my $next_where = $_->{where};
        $_->{where} = $prev_where;

        my $id = $_->{source_class} . '::' . $_->{source_name_for_foreign};
        if ($prev_where) {
            my $where_rule = UR::BoolExpr->resolve($foreign_class, @$where);
            $id .= ' ' . $where_rule->id;

        }
        $id .= ":$join_label";
        $_->{id} = $id; 

        $_->{is_optional} = ($pmeta->is_optional || $pmeta->is_many);

        $_->{is_many} = $pmeta->{is_many};

        $_->{sub_group_label} = $pmeta->property_name;

        $prev_where = $next_where;
    }
    if ($prev_where) {
        Carp::confess("final join needs placement! " . Data::Dumper::Dumper($prev_where));
    }

    for my $join_data (@join_data) {
        push @joins, $class->_get_or_define(%$join_data);
    }

    return @joins;
}


# Return true if the foreign-end of the join includes all the ID properties of
# the foreign class.  Used by the ObjectFabricator when it is determining whether or
# not to include more rules in the all_params_loaded hash for delegations
sub destination_is_all_id_properties {
    my $self = shift;

    my $foreign_class_meta = $self->{'foreign_class'}->__meta__;
    my %join_properties = map { $_ => 1 } @{$self->{'foreign_property_names'}};
    my $join_has_all_id_props = 1;
    foreach my $foreign_id_meta (  $foreign_class_meta->all_id_property_metas ) {
        next if $foreign_id_meta->class_name eq 'UR::Object';  # Skip the manufactured 'id' property
        next if (delete $join_properties{ $foreign_id_meta->property_name });
        $join_has_all_id_props = 0;
    }
    return $join_has_all_id_props;
}


1;
