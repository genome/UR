=head1 NAME

UR::Object::LegacySet - A base class for sets of UR::Objects

=head1 SYNOPSIS

    $s1 = GSC::DNA::Set->create(members => [$o1,$o2,$o3]);
    $s1->add_members($o4,$o5);
    die unless $s1->has_member($o4);
    @o = $s1->get_members; 
    $s1->remove_members($o2,$o4);
    $s1->delete;

=head1 DESCRIPTION

 This is the abstract base class for set objects in the UR::Object system.  It 
 is itself an UR::Object, allowing for sets of sets, persistant sets, and 
 subscriptions to monitor set changes.

 A set is always created with a definition_type, which results in the actual
 created object being subclassed.  The subclass controls access to the members
 of the class, and determines how that membership is recorded.  Sets can be
 explicitly defined to contain particular members, or have a logical definition
 which lets the set change automatically over time.

 The currently available types, and their classes are:*

  explicit                UR::Object::Define::Explicit
  params                  UR::Object::Define::Params
  current revision        UR::Object::Define::CurrentRevision

 A set has a member_type, potentially limiting the type of object stored.  In
 the current implementation, all objects of the specified member_type must have
 a unique identifier, between subclasses.  Mix clones and subclones, but not
 subclones and users.

 If a set is created with the tmp => 1 flag, it will not sync to its underlying
 database.  If not, the set will have a database numeric ID, and will save
 at sync_database.  By default set objects will save in the database which 
 contains their member class' objects.  FOR NOW THEY SAVE TO THE DATA WAREHOUSE.

 *See the UR::Object::LegacySet::Define::* modules for more detail on each definition
  type.  See UR::Object::Define::Example for details on how to write a new
  definition module, and how sets of a new type can define membership.

=cut


package UR::Object::LegacySet;
use warnings;
use strict;
our $VERSION = '0.1';

# Define the class metadata.

##- use UR::Object::Type;

UR::Object::Type->define(
    class_name => 'UR::Object::LegacySet',
    english_name => 'object set',
    id_properties => ['set_id'],
    properties => [
        set_id                           => { type => '', len => undef },
        definition_type                  => { type => '', len => undef },
        member_type                      => { type => '', len => undef },
        set_name                         => { type => '', len => undef },
    ],
);

# This is the dynamic sub-class creator. It ensures that 
# GSC::DNA::Set::DefinitionType::Foo will be dynamically created if 
# GSC::DNA::Set exists and UR::Object::LegacySet::DefinitionType::Foo exists.

# The list of transparent elements allows GSC::DNA::Set::DefinitionType::Foo
# to not expect a GSC::DNA::Set::DefinitionType, but to skip right to a parent of
# GSC::DNA::Set.

our %generated_support_class_transparent = map { $_ => 1 } qw/DefinitionType DefinitionMeta/;

sub generate_support_class {
    my $self = shift;
    my $subject_class_name = ref($self) || $self;
    my $extension_for_support_class = shift;

    if ($generated_support_class_transparent{$extension_for_support_class}) {
        return UR::Object::Type->get(class_name => $subject_class_name);
    }
    
    my $subject_class_obj = UR::Object::Type->get(class_name => $subject_class_name);
    unless ($subject_class_obj)
    {
        $self->error_message("Cannot autogenerate $extension_for_support_class because $subject_class_name does not exist.");
        return;
    }

    my $parent_class_name = __PACKAGE__ . "::" . $extension_for_support_class;
    my $parent_class_obj = UR::Object::Type->get(class_name => $parent_class_name);
    unless ($parent_class_obj)
    {
        $self->error_message("Cannot autogenerate $extension_for_support_class because parent class $parent_class_name does not exist.");
        return;
    }

    my $new_class_name = $subject_class_name . "::" . $extension_for_support_class;    
    my @inheritance = ($parent_class_name);
    push @inheritance, $subject_class_name if $extension_for_support_class =~ /DefinitionType::/;
    my $class_obj = UR::Object::Type->define
    (
        class_name => $new_class_name,
        inheritance => \@inheritance 
    );
    
    return $class_obj;
}

# Attempts to "listen" to changes on a set must work.

sub validate_subscription
{
    my $self = shift;
    my $subscription_property = $_[0];        
    
    # Undefined attributes indicate that the subscriber wants any changes at all to generate a callback.
    return 1 if (!defined($subscription_property));
    
    # All 
    return 1 if ($subscription_property =~ /^(add_member_ids|remove_member_ids)$/);
    
    # A defined attribute for the member is subscribable.
    my $class_object = $self->member_class_name->get_class_object;
    for my $property ($class_object->all_property_names)
    {
        return 1 if ( ("member_" . $property) eq $subscription_property);
    }
    
    # Bad subscription request.
    return $self->SUPER::validate_subscription(@_);
}

sub _init_subclass {
    my ($self, $subclass) = @_;

    my $member_class_name=$subclass->resolve_member_class_name();
    eval "sub ${subclass}::member_class_name { '$member_class_name' }";
    
    # ensure that changes to the member class propagate to the
    # sets of that class as well
    
    if ($subclass =~ /::Set$/ and $subclass ne __PACKAGE__) {
        # A basic listener for this subclass of sets.
        my $member_class_name = $subclass->member_class_name;
        $member_class_name->create_subscription(
            callback => sub {
                my @p = @_;
                my ($self,$property_name,@extra) = @p;
                my $id = $self->id;
                my $set_property_name = "member_" . $property_name;
                my @sets_loaded = $subclass->all_objects_loaded();
                for my $set (@sets_loaded) {
                    if ($set->has_member($self)) {
                        $set->signal_change($set_property_name,@extra);
                    }
                }
            },
            note => "Member change notifier for $subclass.",
            priority => 2,
        ) 
        or die "Failed to attach listener for $subclass";
        
    }

    return 1;
}

# The type of member is constant per concrete subclass.

sub member_class_name {   
    my $self = shift;
    if (ref($self)) {
        my $member_class = UR::Object::Type->get(type_name => $self->member_type);
        return $member_class->class_name;
    }
    else {
        return $self->resolve_member_class_name();
    }
}

sub resolve_member_class_name {
    my $self=shift;
    my $member_class_name = ref($self)||$self;
    $member_class_name =~ s/^(.*)::Set(|::.*?)$/$1/;
    return $member_class_name;
}

# Bridges to metadata

sub meta_member_class_name {
    return $_[0]->member_class_name . "::Set::DefinitionMeta::Membership";
}

sub meta_set_class_name {
    return $_[0]->member_class_name . "::Set::DefinitionMeta::RelatedSet";
}

sub meta_param_class_name {
    return $_[0]->member_class_name . "::Set::DefinitionMeta::Param";
}


# We'd prefer to auto-deduce the subclass from the parameters
# than have the developer specify it explicitly.  This lets us re-factor
# the subclass set over time to be better without changing code.
# The following mapping helps a generic Foo::Set->create(...) work.

our $id = 1000;

our %auto_identified_types = (
    members => "manual",
    member_ids => 'manual',
    params => "parameterized",
    initial_revision_num => "revisionable",
    union => "union",
    intersection => "intersection",
    subtraction => "subtraction",
);


sub create {
    my $class = shift;    
    my %params = @_;
   
    # Parse the name to see if it is complete.
    my ($member_class_name,$class_extension) = ($class =~ /^(.*)::Set(::DefinitionType::.*?|)$/);
       
    # For partially-specified classes, deduce the definition type
    # and delegate to the real class.  It will call this back via SUPER,
    # but only after it's done any required initial processing.
    unless ($class_extension) {
        
        unless ($member_class_name) {
            die "Failed to parse class name $class"
        }
        
        # For partially-specified classes, resolve the def type and then the class.
        my $definition_type;
        if (exists $params{definition_type}) {
            $definition_type = delete $params{definition_type}
        }
        else {
            for my $key (keys %auto_identified_types) {
                if (exists $params{$key}) {
                    $definition_type = $auto_identified_types{$key};
                    last;
                }
            }
        }
        
        unless ($definition_type) {
            die "No definition type specified, and the specified parameters do not resolve to a definition type!";
        }
        
        my @words;
        for my $word (split(/ /,$definition_type)) {
            push @words, ucfirst($word)
        }        
        my $full_class_name = 
            $member_class_name 
            . "::Set::DefinitionType::" 
            . join("",@words);
        
        eval { $full_class_name->class };
        if ($@) {
            die "Unknown definition type '$definition_type'";
        }
        
        return $full_class_name->create(@_, definition_type => $definition_type);
    }    
    
    # Resolve the definition_type.
    my $definition_type = delete $params{definition_type};
    
    # Resolve the member_type.
    my $member_class = UR::Object::Type->get(class_name => $member_class_name);
    unless ($member_class) {
        die "Failed to find class metadata for class: $member_class_name!  Error constructing $class object!"
    }
    my $member_type = $member_class->type_name;
    
    # Create the object.
    # get real class meta if this fails...
    my $self = $class->SUPER::create(
        member_type => $member_type,
        definition_type => $definition_type,
    );
    
    # Notify the change management system.
    return $self;
}

# Base membership checking, changing, and retrieval
# must be implimented in the definition subclass.

# Object-based methods are just wrappers for the id-based ones.

sub has_member {
    my $self = shift;
    my $possible_member_id = $_[0]->id;
    return $self->has_member_id($possible_member_id);    
}

sub get_members {
    my $self = shift;
    my @ids = $self->get_member_ids;
    return unless @ids;
    my $member_class_name = $self->member_class_name;         
    return $member_class_name->get(\@ids);
}


# Operations returning member ids.
# Override for efficiency.

sub union_member_ids {
    my $class;
    $class = shift unless ref($_[0]);
    my %members;
    for my $set (@_) {
        for my $id ($set->get_member_ids) {
            $members{$id} = 1;
        }
    }
    return keys %members;
}

sub intersection_member_ids {
    my $class;
    $class = shift unless ref($_[0]);
    return unless @_;
    my @ids = $_[0]->get_member_ids;
    shift @_;
    for my $set (@_) {
        @ids = $set->get_member_ids(@ids);
        last if not @ids;
    }
    return @ids;
}

# Autogenerate one method for each of the above operations which
# actual objects instead of ids.

for my $op (qw/union intersection/) {
    my $src = qq|
        sub ${op}_members {
            my \$self = shift;
            my \@ids = \$self->${op}_member_ids(\@_);
            return \$self->_id_listref_to_objects(\\\@ids);
        }
        1;
    |;    
    #print $src;
    eval($src) or die($@);
}


# Private utility methods.

sub _id_listref_to_objects {
    return unless @{$_[1]} > 0;
    $_[0]->member_class_name->get($_[1]);
}


1;

=pod

=head1 PROPERTIES

=over 4

=item set_id

 A unique ID which will not be duplicated among sets in the same namespace.
 The name is the first word in the "::"-separated class name.

=item set_name

 A text name which will not be duplicated for a given member type.
 When not explicitly specified, the name is the set_id.
 
=item member_type 

 Returns the type name of the set's members.  This is determined when the set
 is defined and cannot be changed.

=item member_class_name

 Returns the class of member the set contains.  Member class can be abstract
 if the subclasses use a common ID pool.

=item definition_type

 Returns the definition type behind the set.  It is also determined when the
 set is defined and cannot be changed.

=back

=head1 GENERAL METHODS

=over 4

=item create

 The standard constructor for UR::Objects.  This always returns a subclass of
 UR::Object::LegacySet with a class name like $MEMBER_CLASS::Set::DefinitionType::$DEF_TYPE, 
 which inherits from both $MEMBER_CLASS::Set and UR::Object::LegacySet::Define::$DEF_TYPE.

 It typically takes additional parameters which indicate set membership in 
 detail.  For more info see UR::Object::LegacySet::Define::Xxx where xxx is the
 definition type.

=item delete

 The standard destructor.  Makes the object unusable, to be cleaned-up when
 no longer referenced.  This does NOT delete the objects in the set, only
 the grouping of the objects.


=back

=head1 OBJECT-BASED MEMBERSHIP METHODS

=over 4

=item get_members

 Returns all members of the set.  How membership is resolved is determined by
 the specific definition type.

=item has_member

 Tests for the presence of a member in the set.
  
=item add_member

 For sets which have some sort of dynamic manual membership, this method takes 
 one or more objects and adds them to the set.

 Not all sets support this method externally, but all sets support subscriptions
 to it.
 
=item remove_member

 Like add_member, for sets which have some sort of dynamic manual membership, 
 this method takes one or more objects and removes them from the set.

 Not all sets support this method externally, but all sets support subscriptions
 to it.

=back

=head1 ID-BASED MEMBERSHIP METHODS

 The four methods above have ID-based versions as well.
 They all take/return object IDs where the prior methods took objects, and are 
 named as follows:

=over

=item get_member_ids

   Returns just the IDs of the set members.
   
=item add_member_ids

   Takes just the member IDs to be added.
   
=item remove_member_ids

   Takes just the member IDs to removed.
   
=item has_member_id
 
   Tests a given ID for membership.
   
=back

=head1 BUGS

=over

=item signaling system 

  The set needs to emit a signal when objects are added or removed,
  and also when member objects emit a change signal.
  
=item set property method caching

  Since sets can have their own properties, it is important to know what 
  properties of the underlying objects these values are based-on.  The
  signalling system can cache those values, and ensure they are refreshed
  as needed when underlying changes occur.

=item count

  A set should be able to track it's count once asked-for and return that
  value immediately.

=item parameterized sets

  Dynamic parameterized sets are not functioning yet.
  
=item storage

  General database storage is not turned-on yet.  Right now specific subclasses
  can map to a table of their choice, but misc set storage is not present.

=item iterators

  There is an iterator for UR::Entitys, but it needs to be expanded
  to iterate set members, and general returns from get().
  
=item viewers
  
  The viewer is stubbed-out, but not complete.

Report bugs to <software@watson.wustl.edu>.

=back

=head1 SEE ALSO

App(3), UR::Object(3), UR::Object::LegacySet::DefinitionType::Manual(3),

=head1 AUTHOR

Scott Smith <ssmith@watson.wustl.edu>,

# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software.  You may distribute under the terms
# of either the GNU General Public License or the Artistic License, as
# specified in the Perl README file.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

#$Header$
