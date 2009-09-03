package UR::Object::Reference::Property;

use strict;
use warnings;

=cut

UR::Object::Type->define(
    class_name => 'UR::Object::Reference::Property',
    english_name => 'type attribute has a',
    id_properties => [qw/tha_id rank/],
    properties => [
        rank                             => { type => 'NUMBER', len => 2 },
        tha_id                           => { type => 'NUMBER', len => 10 },
        attribute_name                   => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        property_name                    => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        r_attribute_name                 => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        r_property_name                  => { type => 'VARCHAR2', len => 64, is_optional => 1 },
    ],
);

=cut

sub reference_id {
    # forward-compatible alias for the old "type has a" now "reference"
    shift->tha_id
}


# We're overriding get() so these objects can get created on the fly
sub get {
    my $class = shift;

    # Do they already exist?
    my @o = $class->SUPER::get(@_);
    return $class->context_return(@o) if (@o);

    my %params = @_;
    unless ($params{'tha_id'}) {
        if ($params{'class_name'} and $params{'property_name'}) {
            $params{'tha_id'} = $params{'class_name'} . '::' . $params{'property_name'};
        } else {
            Carp::confess("Required parameter (tha_id) missing");
        }
    }
    my $tha_id = $params{'tha_id'};
    my $ref = UR::Object::Reference->get(id => $tha_id);
    unless ($ref) {
        if (ref($tha_id) eq 'ARRAY') {
            $tha_id = '[' . join(',',@$tha_id) . ']: ' . scalar(@$tha_id) . ' items';
        }
        return;  # If there's no reference object, there can't be any reference properties
    }

    my $class_name = $ref->class_name;
    my $class_meta = UR::Object::Type->get(class_name => $class_name);
    my $delegation_property_meta = $class_meta->get_property_meta_by_name($ref->delegation_name);
    unless ($delegation_property_meta) {
        # FIXME - the update_classes testcase trips this conditional up and causes a die here when
        # it's updating the Car class.  A Reference gets created from Car to Person through the foreign key
        # called person_owner, but there's no class property, therefore no reference property
        # But the testcase also implies that it's not expecting a person_owner property, so maybe we just
        # return nothing?
        #Carp::confess("Couldn't find a property called " . $ref->delegation_name . " on class $class_name");
        return;
    }

    my @property_names = @{$delegation_property_meta->{'id_by'}};

    my $r_class_name = $ref->r_class_name;
    my $r_class_meta = UR::Object::Type->get(class_name => $r_class_name);
    my @r_property_names = $r_class_meta->id_property_names;

    unless (scalar(@property_names) == scalar(@r_property_names)) {
        Carp::confess('Unequal property counts describing reference $tha_id.   Property has ' .
                      scalar(@property_names) . " while class $r_class_name has " .
                      scalar(@r_property_names) . ' id properties.');
    }

    my $rank = 0;
    my @defined_objects;
    for (my $i = 0; $i < @property_names; $i++) {
        my $property_name = $property_names[$i];
        my $property_meta = $class_meta->get_property_meta_by_name($property_name);
        my $attribute_name = $property_meta->attribute_name;

        my $r_property_name = $r_property_names[$i];
        #my $r_property_meta = UR::Object::Property->get(class_name => $r_class_name, property_name => $r_property_name);
        my $r_property_meta = $r_class_meta->get_property_meta_by_name($r_property_name);
        my $r_attribute_name = $r_property_meta->attribute_name;

        my $rp = UR::Object::Reference::Property->define(
                     tha_id           => $tha_id,
                     rank             => $i+1,
                     property_name    => $property_name,
                     attribute_name   => $attribute_name,
                     r_property_name  => $r_property_name,
                     r_attribute_name => $r_attribute_name,
                 );
        unless ($rp) {
            Carp::confess('Failed to define relationship ' . $ref->delegation_name . " property $property_name");
        }

        {
            use Data::Dumper; 
            no strict;
            my $db_committed = eval(Data::Dumper::Dumper($rp));
            $rp->{'db_committed'} ||= $db_committed;
            delete $db_committed->{'id'};
        }

        push @defined_objects, $rp;
    }

    $class->context_return(@defined_objects);
}

sub create_object
{
    my $class = shift;
    my %params = @_;
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
    if ($params{r_attribute_name} and not $params{r_property_name}) {
        my $r_property_name = $params{r_attribute_name};
        $r_property_name =~ s/ /_/g;
        $params{r_property_name} = $r_property_name;
    }
    elsif ($params{r_property_name} and not $params{r_attribute_name}) {
        my $r_attribute_name = $params{r_property_name};
        $r_attribute_name =~ s/_/ /g;
        $params{r_attribute_name} = $r_attribute_name;
    }
    return $class->SUPER::create_object(%params);
}

sub _reference_class
{
    my $self = shift;
    if ($self->isa('UR::Object::Ghost')) {
        return 'UR::Object::Reference::Ghost';
    }
    else {
        return 'UR::Object::Reference';
    }
}

sub get_reference
{
    my $self = shift;
    return $self->_reference_class->get($self->tha_id);
}

sub class_name
{
    my $self = shift;
    my $r = $self->get_reference;
    return $r->class_name;
}


sub r_class_name
{
    shift->get_reference->r_class_name
}

sub get_with_special_parameters 
{
    my $class = shift;
    my $rule = shift;
    my %extra = @_;    
    if (my $class_name = delete $extra{class_name}) {
        unless (keys %extra) {
            # turn the class name into one or more ids for UR::Object::Reference.
            my @r = UR::Object::Reference->get(class_name => $class_name);
            return $class->get($rule->params_list, tha_id => \@r);
        }
    } elsif (my $r_class_name = delete $extra{r_class_name}) {
        unless (keys %extra) {
            # turn the class name into one or more ids for UR::Object::Reference.
            my @r = UR::Object::Reference->get(r_class_name => $r_class_name);
            return $class->get($rule->params_list, tha_id => \@r);
        }
    }
    return $class->SUPER::get_with_special_parameters($rule,@_);
}

1;
