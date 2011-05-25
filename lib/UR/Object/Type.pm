package UR::Object::Type;

use warnings;
use strict;
require UR;

# Used during bootstrapping.
our @ISA = qw(UR::Object);
our $VERSION = "0.31"; # UR $VERSION;;

our @CARP_NOT = qw( UR::Object UR::Context  UR::ModuleLoader Class::Autouse UR::BoolExpr );

# Most of the API for this module are legacy internals required by UR.
use UR::Object::Type::InternalAPI;

# This module implements define(), and most everything behind it.
use UR::Object::Type::Initializer;

# The methods used by the initializer to write accessors in perl.
use UR::Object::Type::AccessorWriter;

# The methods to extract/(re)create definition text in the module source file.
use UR::Object::Type::ModuleWriter;

# Present the internal definer as an external method
sub define { shift->__define__(@_) }

# For efficiency, certain hash keys inside the class cache property metadata
# These go in this array, and are cleared when property metadata is mutated
our @cache_keys;

# This is the function behind $class_meta->properties(...)
# It mimics the has-many object accessor, but handles inheritance
# Once we have "isa" and "is-parent-of" operator we can do this with regular operators.
push @cache_keys, '_properties';
sub _properties {
    my $self = shift;
    my $all = $self->{_properties} ||= do {
        # start with everything, as it's a small list
        my $map = $self->_property_name_class_map;
        my @all;
        for my $property_name (sort keys %$map) {
            my $class_names = $map->{$property_name};
            my $class_name = $class_names->[0];
            my $id = $class_name . "\t" . $property_name;
            my $property_meta = UR::Object::Property->get($id);
            unless ($property_meta) {
                Carp::confess("Failed to find property meta for $class_name $property_name?");
            }
            push @all, $property_meta; 
        }
        \@all;
    };
    if (@_) {
        my $bx = UR::Object::Property->define_boolexpr(@_);
        my @matches = grep { $bx->evaluate($_) } @$all; 
        return if not defined wantarray;
        return @matches if wantarray;
        die "Matched multiple meta-properties, but called in scalar context!" . Data::Dumper::Dumper(\@matches) if @matches > 1;
        return $matches[0];
    }
    else {
        @$all;
    }
}

sub property {
    if (@_ == 2) {
        # optimize for the common case
        my ($self, $property_name) = @_;
        my $class_names = $self->_property_name_class_map->{$property_name};
        my $id = $class_names->[0] . "\t" . $property_name;
        return UR::Object::Property->get($id); 
<<<<<<< HEAD
    }
    else {
        # this forces scalar context, raising an exception if
        # the params used result in more than one match
        my $one = shift->properties(@_);
        return $one;
    }
}

push @cache_keys, '_property_names';
sub property_names {
    my $self = $_[0];
    my $names = $self->{_property_names} ||= do {
        my @names = sort keys %{ shift->_property_name_class_map };
        \@names;
    };
    return @$names;
}

push @cache_keys, '_property_name_class_map';
sub _property_name_class_map {
    my $self = shift;
    my $map = $self->{_property_name_class_map} ||= do {
        my %map = ();  
        for my $class_name ($self->class_name, $self->ancestry_class_names) {
            my $class_meta = UR::Object::Type->get($class_name);
            if (my $has = $class_meta->{has}) {
                for my $key (sort keys %$has) {
                    my $classes = $map{$key} ||= [];
                    push @$classes, $class_name;
                }
            }
        }
        \%map;
    };
    return $map;
=======
    }
    else {
        # this forces scalar context, raising an exception if
        # the params used result in more than one match
        my $one = shift->properties(@_);
        return $one;
    }
}

push @cache_keys, '_property_names';
sub property_names {
    my $self = $_[0];
    my $names = $self->{_property_names} ||= do {
        my @names = sort keys %{ shift->_property_name_class_map };
        \@names;
    };
    return @$names;
}

push @cache_keys, '_property_name_class_map';
sub _property_name_class_map {
    my $self = shift;
    my $map = $self->{_property_name_class_map} ||= do {
        my %map = ();  
        for my $class_name ($self->class_name, $self->ancestry_class_names) {
            my $class_meta = UR::Object::Type->get($class_name);
            if (my $has = $class_meta->{has}) {
                for my $key (sort keys %$has) {
                    my $classes = $map{$key} ||= [];
                    push @$classes, $class_name;
                }
            }
        }
        \%map;
    };
    return $map;
}

sub _legacy_properties {
    my $self = shift;
    if (@_) {
        my $bx = UR::Object::Property->define_boolexpr(@_);
        my @matches = grep { $bx->evaluate($_) } $self->property_metas;
        return if not defined wantarray;
        return @matches if wantarray;
        die "Matched multiple meta-properties, but called in scalar context!" . Data::Dumper::Dumper(\@matches) if @matches > 1;
        return $matches[0];
    }
    else {
        $self->property_metas;
    }
>>>>>>> master
}

1;

=pod

=head1 NAME

UR::Object::Type - a meta-class for any class or primitive type 

=head1 SYNOPSIS

    use UR;

    class MyClass {
        is => ['ParentClass1', 'ParentClass2'],
        id_by => [
            id_prop1    => { is => 'Integer' },
            id_prop2    => { is => 'String' },
        ],
        has => [
            property_a  => { is => 'String' }
            property_b  => { is => 'Integer', is_optional => 1 },
        ],
    };

    my $meta = MyClass->__meta__;
    
    my @parent_class_metas = $meta->parents();
    # 2 meta objects, see UR::Object::Property

    my @property_meta = $meta->properties();
    # N properties (4, +1 from UR::Object, +? from ParentClass1 and ParentClass2)
    
    $meta->is_abstract;

    $meta->...

=head1 DESCRIPTION

UR::Object::Type implements the class behind the central metadata in the UR
class framework.  It contains methods for introspection and manipulation of 
related class data.  

A UR::Object::Type object describes UR::Object, and also
every subclass of UR::Object.

=head1 INHERITANCE

Each sub-class of UR::Object has a single UR::Object::Type object
describing the class.  The UR::Object class itself also has
a UR::Object::Type object describing the base class of the system.

In addition to describing UR::Object an each of its subclasses, 
UR::Object::Type is _itself_ a subclass of L<UR::Object>.  This means
that the same query APIs used for regular objects can be used
for meta objects.
                                       /-----------------------\ 
                                      V                         |
   UR::Object  -> has-meta -> UR::Object::Type --> has-meta >--/  
          A                         |
          \                        / 
           \-----<- is-a  <-------/

Further, new classes which generate a new UR::Object::Type,
also generate a private subclass for the meta-class.  This
means that each new class can have private meta methods,
(ala Ruby). 

This also means that extensions to a meta-class,
apply to the meta-class of its derivatives.

        Regular                    Meta-Class 
        Entity                     Singleton
        -------                    ----------

        Greyhound   has-meta ->   Greyhound::Type
            |                          |
            V                          V
          is-a                       is-a 
            |                          |
            V                          V
           Dog      has-meta ->    Dog::Type
            |                          |
            V                          V
          is-a                       is-a
            |                          |
            V                          V
         Animal     has-meta ->   Animal::Type        
            |                          |
            V                          V
          is-a                       is-a
            |                          |     /-----------------\
            V                          V     V                 |
       UR::Object   has-meta ->   UR::Object::Type   has-meta -/ 
            A                        is-a
            |                          |
             \________________________/


=head1 CONSTRUCTORS

=over 4

=item "class" 

  class MyClass1 {};

  class MyClass2 { is => 'MyClass1' };

  class MyClass3 {
      is => ['Parent1','Parent2'],
      is_abstract => 1,
      is_transient => 1,
      has => [ qw/p1 p2 p3/ ],
      doc => 'woo hoo!'
  };

The primary constructor is not a method on this class at all.
UR catches "class SOMENAME { ... }" and calls define() with
the parameters.

=item define

  my $class_obj = UR::Object::Type->define(
                      class_name => 'MyClass',
                      ...
                  );

Register a class with the system.  The given class_name must be unique
within the application.  As a side effect, a new Perl namespace will be
created for the class's name, and methods will be injected into that
namespace for any of the class properties.  Other types of metadata
objects will get created to manage the properties and relationships
to other classes.  See the L<UR::Object::Type::Initializer> documentation
for more information about the parameters C<define()> accepts.

=item create

  my $class_obj = UR::Object::Type->create(
                      class_name => 'Namespace::MyClass',
                      ...
                  );

Create a brand new class within an already existing UR namespace.
C<create()> takes all the same parameters as C<define()>.  Another side
effect of create is that when the application commits its Context,
a new Perl module will be created to implement the class, complete 
with a class definition.  

Applications will not normally use create().

=back

=head1 PROPERTIES

Each property has a method of the same name

=head2 External API 

=over 4

=item class_name

    $name = $class_obj->class_name

The full name of the class.  This is symmetrical with $class_obj = $name->__meta__.

=item properties

  @all = $class_obj->properties();
  
  @some = $class_obj->properties(
      'is                    => ['Text','Number']
      'doc like'             => '%important%',
      'property_name like'   => 'someprefix_%',
  );

Access the related property meta-objects for all properties of this class.  It includes 
the properties of any parent classes which are inherited by this class.

See L<UR::Object::Property> for details.

=item property

  $property_meta = $class_obj->property('someproperty');

The singular version of the above.  A single argument, as usual, is treated
as the remainder of the ID, and will select a property by name.

=item property_names 

  @names = $class_obj->property_names;

Returns a list of all properties belonging to the class, directly
or through inheritance.

=item namespace

  $namespace_name = $class_obj->namespace

Returns the name of the class's UR namespace.

=item doc

  $doc = $class_obj->doc

A place to put general class-specific notes.

=item data_source_id

  $ds_id = $class_obj->data_source_id

The name of the external data source behind this class.  Classes without
data sources cannot be saved and exist only during the life of the
application.  data_source_id will resolve to an L<UR::DataSource> id.

=item table_name

  $table_name = $class_object->table_name

For classes with data sources, this is the name of the table within that
data source.  This is usually a table in a relational database.

At a basic level, it is a storage directive interpreted by the data_source,
and may or may not related to a storage table at that level.

=item is_abstract

  $bool = $class_obj->is_abstract

A flag indicating if this is an abstract class.  Abstract classes cannot have
instances, but can be inherited by other classes.

=item is_final

  $bool = $class_obj->is_final

A flag indicating if this class cannot have subclasses.

=item is_singleton

  $bool = $class_obj->is_singleton

A flag indicating whether this is a singleton class.  If true, the class
will inherit from L<UR::Singleton>.

=item is_transactional

  $bool = $class_obj->is_transactional

A flag indicating whether changes to this class's instances will be tracked.
Non-transactional objecs do not change when an in-memory transaction rolls back.

It is similar to the is_transient meta-property, which does the same for an 
individual property.

=back

=head2 Internal API 

These methods return data about how this class relates to other classes.

=over 4

=item namespace_meta

  $ns_meta = $class_obj->namespace_meta

Returns the L<UR::Namespace> object with the class's namespace name.

=item parent_class_names

  @names = $class_obj->parent_class_names

Returns a list of the immediate parent classes.  

=item parent_class_metas

  @class_objs = $class_obj->parent_class_metas

Returns a list of the class objects (L<UR::Object::Type> instances) of the
immediate parent classes

=item ancestry_class_names

  @names = $class_obj->ancestry_class_names

Returns a list of all the class names this class inherits from, directly or 
indirectly.  This list may have duplicate names if there is multiple
inheritance in the family tree.

=item ancestry_class_metas

  @class_objs = $class_obj->ancestry_class_metas

Returns a list of the class objects for each inherited class.

=item direct_property_names

  @names = $class_obj->direct_property_names

Returns a list of the property names defined within this class.  This list
will not include the names of any properties inherited from parent classes
unless they have been overridden.

=item direct_property_metas

  @property_objs = $class_obj->direct_property_metas

Returns a list of the L<UR::Object::Property> objects for each direct
property name.

=item ancestry_property_names

  @names = $class_obj->ancestry_property_names

Returns a list of property names of the parent classes and their inheritance
heirarchy.  The list may include duplicates if a property is overridden
somewhere in the heirarchy.

=item ancestry_property_metas

  @property_objs = $class_obj->ancestry_property_metas;

Returns a list of the L<UR::Object::Property> objects for each ancestry
property name.

=item all_property_names

Returns a list of property names of the given class and its inheritance
heirarchy.  The list may include duplicates if a property is overridden
somewhere in the heirarchy.

=item all_property_metas

  @property_objs = $class_obj->all_property_metas;

Returns a list of the L<UR::Object::Property> objects for each name returned
by all_property_names.

=item direct_id_property_names

  @names = $class_obj->direct_id_property_names

Returns a list of the property names designated as "id" properties in the
class definition.

=item direct_id_property_metas

  @property_objs = $class_obj->direct_id_property_metas

Returns a list of the L<UR::Object::Property> objects for each id property
name.

=item ancestry_id_property_names

=item ancestry_id_property_metas

=item all_id_property_names

=item all_id_property_metas

  @names         = $class_obj->ancestry_id_property_names;
  @property_objs = $class_obj->ancestry_id_property_metas;
  @names         = $class_obj->all_id_property_names;
  @property_objs = $class_obj->all_id_property_metas;

Returns the property names or L<UR::Object::Property> objects for either
the parent classes and their inheritance heirarchy, or for the given
class and all of its inheritance heirarchy.  The lists may include duplicates
if properties are overridden somewhere in the heirarchy.

=item unique_property_set_hashref

  $constraints = $class_obj->unique_property_set_hashref

Return a hashref describing the unique constraints on the given class.  The
keys of $constraint are constraint names, and the values are listrefs of 
property names that make up the unique constraint.

=item add_unique_constraint

  $class_obj->add_unique_constraint($constraint_name, @property_name_list)

Add a unique constraint to the given class.  It is an exception if the
given $constraint_name already exists as a constraint on this class or
its parent classes.

=item remove_unique_constraint

  $class_obj->remove_unique_constraint($constraint_name)

Remove a unique constraint from the given class.  It is an exception if
the given constraint name does not exist.

=item ancestry_table_names

=item all_table_names

  @names = $class_obj->ancestry_table_names

Returns a list of table names in the class's inheritance heirarchy.

=item direct_column_names

Returns a list of column names for each direct property meta.  Classes with
data sources and table names will have properties with column names.

=item direct_id_column_names

Returns a list of ID column names for each direct property meta.

=item direct_columnless_property_names

=item direct_columnless_property_metas

=item ancestry_columnless_property_names

=item ancestry_columnless_property_metas

=item all_columnless_property_names

=item all_columnless_property_metas

Return lists of property meta objects and their names for properties that
have no column name.

=head1 METHODS

=item property_meta_for_name

  $property_obj = $class_obj->property_meta_for_name($property_name);

Return the L<UR::Object::Property> object in the class's inheritance
hierarchy with the given name.  If the property name has been overridden
somewhere in the hierarchy, then it will return the property object
most specific to the class.

=item id_property_sorter

  $subref = $class_obj->id_property_sorter;
  @sorted_objs = sort $subref @unsorted_objs;

Returns a subroutine reference that can be used to sort object instances of
the class.  The subref is able to handle classes with multiple ID 
properties, and mixes of numeric and non-numeric data and data types.

=item autogenerate_new_object_id

This method is called whenever new objects of the given class are created
through C<ClassName-E<gt>create()>, and not all of their ID properties were
specified.  UR::Object::Type has an implementation used by default, but
other classes can override this if they need special handling.

=back

=head1 SEE ALSO

L<UR::Object::Property>

=cut


