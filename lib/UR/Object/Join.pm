package UR::Object::Join;
use strict;
use warnings;
use UR;

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
        
        is_optional             => { is => 'Text' }, 

        where                   => { is => 'Text' },
    ],
    doc => "join metadata used internally by the ::QueryBuilder"
};

sub resolve_chain_for_property_meta {
    my ($class, $pmeta) = @_;  
    if ($pmeta->via or $pmeta->to) {
        return $class->_resolve_via_to($pmeta);
    }
    else {
        my @j = eval {
            my $foreign_class = $pmeta->_data_type_as_class_name;
            unless (defined($foreign_class) and $foreign_class->can('get'))  {
                return;
            }
            if ($pmeta->id_by or $foreign_class->isa("UR::Value")) {
                return $class->_resolve_forward($pmeta);
            }
            elsif (my $reverse_as = $pmeta->reverse_as) { 
                return $class->_resolve_reverse($pmeta);
            }
            else {
                # TODO: handle hard-references to objects here maybe?
                $pmeta->error_message("Property " . $pmeta->id . " has no 'id_by' or 'reverse_as' property metadata");
                return;
            }
        };
        die $@ if $@;
        if (grep { ref($_) ne __PACKAGE__ } @j) { 
            $DB::single = 1;
            #$class->resolve_chain_for_property_meta($pmeta);
            Carp::confess(Data::Dumper::Dumper(\@j)) 
        };
        #print Data::Dumper::Dumper(\@j);
        return @j;
    }
}

sub _get_or_define {
    my $class = shift;
    my %p = @_;
    my $id = delete $p{id};
    delete $p{__get_serial};
    delete $p{db_committed};
    delete $p{_change_count};
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
    my ($class, $pmeta) = @_;
    my $class_meta = UR::Object::Type->get(class_name => $pmeta->class_name);

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
            my $property_name = $pmeta->property_name;
            my $class_name = $pmeta->class_name;
            Carp::croak "Can't resolve property '$property_name' of $class_name: No via meta for '$via'?";
        }

        if ($via_meta->to and ($via_meta->to eq '-filter')) {
            return $via_meta->_resolve_join_chain;
        }

        unless ($via_meta->data_type) {
            my $property_name = $pmeta->property_name;
            my $class_name = $pmeta->class_name;
            Carp::croak "Can't resolve property '$property_name' of $class_name: No data type for '$via'?";
        }
        push @joins, $via_meta->_resolve_join_chain();
        
        if (my $where = $pmeta->where) {
            my $join = pop @joins;
            unless ($join->{foreign_class}) {
                Carp::confess("No foreign class in " . Data::Dumper::Dumper($join, \@joins));
            }
            my $where_rule = UR::BoolExpr->resolve($join->{foreign_class}, @$where);                
            my $id = $join->{id};
            $id .= ' ' . $where_rule->id;
            
            my %join_data = %$join;
            push @joins, $class->_get_or_define(%join_data, id => $id, where => $where);
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

        push @joins, $to_meta->_resolve_join_chain();
    }
    
    return @joins;
}

# code below uses these to convert objects using hash slices
my @old = qw/source_class source_property_names foreign_class foreign_property_names source_name_for_foreign foreign_name_for_source is_optional/;
my @new = qw/foreign_class foreign_property_names source_class source_property_names foreign_name_for_source source_name_for_foreign is_optional/;

sub _resolve_forward {
    my ($class, $pmeta) = @_;

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
            
                push @joins, $id_by_property->_resolve_join_chain();
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

    push @joins, $class->_get_or_define( 
                    id => $id,

                    source_class => $source_class,
                    source_property_names => \@source_property_names,
                    
                    foreign_class => $foreign_class,
                    foreign_property_names => \@foreign_property_names,
                    
                    source_name_for_foreign => $source_name_for_foreign,
                    foreign_name_for_source => $foreign_name_for_source,
                    
                    is_optional => ($pmeta->is_optional or $pmeta->is_many),

                    where => $where,
                );

    return @joins;
}

sub _resolve_reverse {
    my ($class, $pmeta) = @_;

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

    my @join_data = map { { %$_ } } reverse $foreign_property_via->_resolve_join_chain();
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
        $_->{id} = $id; 

        $_->{is_optional} = ($pmeta->is_optional || $pmeta->is_many);
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

1;
