package UR::Object::Property;

use warnings;
use strict;
require UR;
use Lingua::EN::Inflect;
use Class::AutoloadCAN;

our $VERSION = "0.30"; # UR $VERSION;;
our @CARP_NOT = qw( UR::DataSource::RDBMS UR::Object::Type );

# TODO: make these methods on UR::Value::Type metadata
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

# TODO: This is used by the code which maps RDBMS tables to 
# UR types, and should really be in the RDBMS datasource and its subclasses.
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

# TODO: this is a method on the data source which takes a given property.
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

sub final_property_meta {
    my $self = shift;

    my $closure;
    $closure = sub { 
        return unless defined $_[0];
        if ($_[0]->is_delegated and $_[0]->via) {
            if ($_[0]->to) {
                return $closure->($_[0]->to_property_meta);
            } else {
                return $closure->($_[0]->via_property_meta);
            }
        } else {
            return $_[0];
        }
    };
    my $final = $closure->($self);

    return if !defined $final || $final->id eq $self->id;
    return $final;
}

# For via/to delegated properties, return the property meta on the foreign
# class that this property delegates to
sub to_property_meta {
    my $self = shift;

    return unless ($self->is_delegated && $self->to);

    my $via_meta = $self->via_property_meta();
    return unless $via_meta;

    my $remote_class = $via_meta->data_type;
#    unless ($remote_class) {
#        # Can we guess what the data type is for multiply indirect properties?
#        if ($via_meta->to) {
#            my $to_property_meta = $via_meta->to_property_meta;
#            $remote_class = $to_property_meta->data_type if ($to_property_meta);
#        }
#    }
    return unless $remote_class;
    my $remote_class_meta = UR::Object::Type->get($remote_class);
    return unless $remote_class_meta;

    return $remote_class_meta->property_meta_for_name($self->to);
}


sub get_property_name_pairs_for_join {
    my ($self) = @_;
    my @linkage = $self->_get_direct_join_linkage();
    unless (@linkage) {
        Carp::croak("Cannot resolve underlying property joins for property ".$self->id);
    }
    if ($self->reverse_as) {
        return map { [ $_->[1] => $_->[0] ] } @linkage;
    } else {
        return map { [ $_->[0] => $_->[1] ] } @linkage;
    }
}

sub _get_direct_join_linkage {
    my ($self) = @_;
    my @retval;
    if (my $id_by = $self->id_by) {
        my $r_class_meta = $self->r_class_meta;
        unless ($r_class_meta) {
            Carp::croak("Property '" . $self->property_name . "' of class '" . $self->class_name . "' "
                        . "has data_type '" . $self->data_type ."' with no class metadata");
        }

        my @my_id_by = @{ $self->id_by };
        my @their_id_by = @{ $r_class_meta->{'id_by'} };
        unless (@their_id_by) {
            @their_id_by = ( 'id' );
        }
        unless (@my_id_by == @their_id_by) {
            Carp::croak("Property '" . $self->property_name . "' of class '" . $self->class_name . "' "
                        . "has " . scalar(@my_id_by) . " id_by elements, while its data_type ("
                        . $self->data_type .") has " . scalar(@their_id_by));
        }

        for (my $i = 0; $i < @my_id_by; $i++) {
            push @retval, [ $my_id_by[$i], $their_id_by[$i] ];
        }

    }
    elsif (my $reverse_as = $self->reverse_as) {
        my $r_class_name = $self->data_type;
        @retval = 
            $r_class_name->__meta__->property_meta_for_name($reverse_as)->_get_direct_join_linkage();
    }
    return @retval;
}

# These are used to reverse the relationship when we're dealing with reverse_as properites
my @old = qw/source_class source_property_names foreign_class foreign_property_names/;
my @new = qw/foreign_class foreign_property_names source_class source_property_names/;
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
                Carp::croak "Can't resolve property '$property_name' of $class_name: No via meta for '$via'?";
            }

            if ($via_meta->to and ($via_meta->to eq '-filter')) {
                return $via_meta->_get_joins;
            }

            unless ($via_meta->data_type) {
                my $property_name = $self->property_name;
                my $class_name = $self->class_name;
                Carp::croak "Can't resolve property '$property_name' of $class_name: No data type for '$via'?";
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
                my $where_rule = UR::BoolExpr->resolve($join->{foreign_class}, @$where);                
                my $id = $join->{id};
                $id .= ' ' . $where_rule->id;
                push @joins, { %$join, id => $id, where => $where };
            }
            unless ($to eq '__self__' or $to eq '-filter') {
                my $to_class_meta = eval { $via_meta->data_type->__meta__ };
                unless ($to_class_meta) {
                    Carp::croak("Can't get class metadata for " . $via_meta->data_type
                                . " while resolving property '" . $self->property_name . "' in class " . $self->class_name . "\n"
                                . "Is the data_type for property '" . $via_meta->property_name . "' in class "
                                . $via_meta->class_name . " correct?");
                }

                my $to_meta = $to_class_meta->property_meta_for_name($to);
                unless ($to_meta) {
                    my $property_name = $self->property_name;
                    my $class_name = $self->class_name;
                    Carp::croak "Can't resolve property '$property_name' of $class_name: No '$to' property found on " . $via_meta->data_type;
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
                    my $where_rule = UR::BoolExpr->resolve($foreign_class, @$where);
                    $id .= ' ' . $where_rule->id;
                }
                if (my $id_by = $self->id_by) { 
                    my(@source_property_names, @foreign_property_names);
                    # This ensures the linking properties will be in the right order
                    my @pairs = $self->get_property_name_pairs_for_join;
                    @source_property_names  = map { $_->[0] } @pairs;
                    @foreign_property_names = map { $_->[1] } @pairs;
               
                    if (ref($id_by) eq 'ARRAY') {
                        # satisfying the id_by requires joins of its own
                        foreach my $id_by_property_name ( @$id_by ) {
                            my $id_by_property = $class_meta->property_meta_for_name($id_by_property_name);
                            next unless ($id_by_property and $id_by_property->is_delegated);
                           
                            push @joins, $id_by_property->_get_joins();
                            $source_class = $joins[-1]->{'foreign_class'};
                            @source_property_names = @{$joins[-1]->{'foreign_property_names'}};
                        }
                    }

                    push @joins, {
                                   id => $id,
                                   source_class => $source_class,
                                   source_property_names => \@source_property_names,
                                   foreign_class => $foreign_class,
                                   foreign_property_names => \@foreign_property_names,
                                   where => $where,
                                 };
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
                    $joins[0]->{'where'} = $where if $where;

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


sub label_text {
    # The name of the property in friendly terms.
    my ($self,$obj) = @_;
    my $attribute_name = $self->attribute_name;
    my @words = App::Vocabulary->filter_vocabulary(map { ucfirst(lc($_)) } split(/\s+/,$attribute_name));
    my $label = join(" ", @words);
    return $label;
}

# This gets around the need to make a custom property subclass
# when a class has an attributes_have specification.

# This primary example of this in base infrastructure is that
# all Commands have is_input, is_output and is_param attributes.

# Note: it's too permissive and will make an accessor for any hash key.
# The updated code should not do this.

sub CAN {
    my ($thisclass, $method, $self) = @_;
    if (ref($self)) {
        my $accessor_key = '_' . $method . "_accessor";
        if (my $method = $self->{$accessor_key}) {
            return $method;
        }
        if (exists $self->class_name->__meta__->{attributes_have}{$method}) {
            return $self->{$accessor_key} = sub {
                return $_[0]->{$method};
            }
        }
    }
    return;
}


1;

=pod

=head1 NAME

UR::Object::Property - Class representing metadata about a class property

=head1 SYNOPSIS

  my $prop = UR::Object::Property->get(class_name => 'Some::Class', property_name => 'foo');

  my $class_meta = Some::Class->__meta__;
  my $prop2 = $class_meta->property_meta_for_name('foo');

  # Print out the meta-property name and its value of $prop2
  print map { " $_ : ".$prop2->$_ }
        qw(class_name property_name data_type default_value);

=head1 DESCRIPTION

Instances of this class represent properties of classes.  For every item
mentioned in the 'has' or 'id_by' section of a class definition become Property
objects.  

=head1 INHERITANCE

UR::Object::Property is a subclass of L<UR::Object>

=head1 PROPERTY TYPES

For this class definition:
  class Some::Class {
      has => [
          other_id => { is => 'Text' },
          other    => { is => 'Some::Other', id_by => 'foo_id' },
          bar      => { via => 'other', to => 'bar' },
          foos     => { is => 'Some::Foo', reverse_as => 'some', is_many => 1 },
          uc_other_id => { calculate_from => 'other_id',
                           calculate_perl => 'uc($other_id)' },
      ],
  };
      
Properties generally fall in to one of these categories:

=over 4

=item regular property

A regular property of a class holds a single scalar.  In this case,
'other_id' is a regular property.

=item object accessor

An object accessor property returns objects of some class.  The properties
of this class must link in some way with all the ID properties of the remote
class (the 'is' declaration).  'other' is an object accessor property.  This
is how one-to-one relationships are implemented.

=item via property

When a class has some object accessor property, and it is helpful for an
object to assumme the value of the remote class's properties, you can set 
up a 'via' property.  In the example above, an object of this class 
gets the value of its 'bar' property via the 'other' object it's linked
to, from that object's 'bar' property.

=item reverse as or is many property

This is how one-to-many relationships are implemented.  In this case, 
the Some::Foo class must have an object accessor property called 'some',
and the 'foos' property will return a list of all the Some::Foo objects
where their 'some' property would have returned that object.

=item calculated property

A calculated property doesn't store its data directly in the object, but 
when its accessor is called, the calculation code is executed.

=back

=head1 PROPERTIES

Each property has a method of the same name

=head2 Direct Properties

=over 4

=item class_name => Text

The name of the class this Property is attached to

=item property_name => Text

The name of the property.  The pair of class_name and property name are
the ID properties of UR::Object::Property

=item column_name => Text

If the class is backed by a database table, then the column this property's 
data comes from is stored here

=item data_type => Text

The type of data stored in this property.  Corresponds to the 'is' part of
a class's property definition.

=item data_length => Number

The maximum size of data stored in this property

=item default_value

For is_optional properties, the default value given when an object is created
and this property is not assigned a value.

=item valid_values => ARRAY

A listref of enumerated values this property may be set to

=item doc => Text

A place for documentation about this property

=item is_id => Boolean

Indicates whether this is an ID property of the class

=item is_optional => Boolean

Indicates whether this is property may have the value undef when the object
is created

=item is_transient => Boolean

Indicates whether this is property is transient?

=item is_constant => Boolean

Indicates whether this property can be changed after the object is created.

=item is_mutable => Boolean

Indicates this property can be changed via its accessor.  Properties cannot
be both constant and mutable

=item is_volatile => Boolean

Indicates this property can be changed by a mechanism other than its normal
accessor method.  Signals are not emmitted even when it does change via
its normal accessor method.

=item is_classwide => Boolean

Indicates this property's storage is shared among all instances of the class.
When the value is changed for one instance, that change is effective for all
instances.

=item is_delegated => Boolean

Indicates that the value for this property is not stored in the object
directly, but is delegated to another object or class.

=item is_calculated => Boolean

Indicates that the value for this property is not a part of the object'd
data directly, but is calculated in some way.

=item is_transactional => Boolean

Indicates the changes to the value of this property is tracked by a Context's
transaction and can be rolled back if necessary.

=item is_abstract => Boolean

Indicates this property exists in a base class, but must be overridden in
a derived class.

=item is_concrete => Boolean

Antonym for is_abstract.  Properties cannot be both is_abstract and is_concrete,

=item is_final => Boolean

Indicates this property cannot be overridden in a derived class.

=item is_deprecated => Boolean

Indicates this property's use is deprecated.  It has no effect in the use
of the property in any way, but is useful in documentation.

=item implied_by => Text

If this propery is created as a result of another property's existence,
implied_by is the name of that other property.  This can happen in the
case where an object accessor property is defined

  has => [ 
      foo => { is => 'Some::Other', id_by => 'foo_id' },
  ],

Here, the 'foo' property requires another property called 'foo_id', which
is not explicitly declared.  In this case, the Property named foo_id will
have its implied_by set to 'foo'.

=item id_by => ARRAY

In the case of an object accessor property, this is the list of properties in
this class that link to the ID properties in the remote class.

=item reverse_as => Text

Defines the linking property name in the remote class in the case of an
is_many relationship

=item via => Text

For a via-type property, indicates which object accessor to go through.

=item to => Text

For a via-type property, indicates the property name in the remote class to
get its value from.  The default value is the same as property_name

=item where => ARRAY

Supplies additional filters for indirect properies.  For example:

  foos => { is => 'Some::Foo', reverse_as => 'some', is_many => 1 },
  blue_foos => { via => 'foos', where => [ color => 'blue' ] },

Would create a property 'blue_foos' which returns only the related
Some::Foo objects that have 'blue' color.

=item calculate_from => ARRAY

For calculated properties, this is a list of other property names the
calculation is based on

=item calculate_perl => Text

For calculated properties, a string containing Perl code.  Any properties
mentioned in calculate_from will exist in the code's scope at run time
as scalars of the same name.

=item class_meta => UR::Object::Type

Returns the class metaobject of the class this property belongs to

=back

=head1 METHODS

=over 4

=item via_property_meta

For via/to delegated properties, return the property meta in the same
class this property delegates through

=item to_property_meta

For via/to delegated properties, return the property meta on the foreign
class that this property delegates to

=back

=head1 SEE ALSO

UR::Object::Type, UR::Object::Type::Initializer, UR::Object

=cut
