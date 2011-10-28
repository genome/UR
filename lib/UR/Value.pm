package UR::Value;

use strict;
use warnings;

require UR;
our $VERSION = "0.35"; # UR $VERSION;

our @CARP_NOT = qw( UR::Context );

UR::Object::Type->define(
    class_name => 'UR::Value',
    is => 'UR::Object',
);

sub __display_name__ {
    my $self = $_[0];
    return $self->id;
}

sub _load {
    my $class = shift;    
    my $rule = shift;

    # See if the requested object is loaded.
    my @loaded = $UR::Context::current->get_objects_for_class_and_rule($class,$rule,0);
    return $class->context_return(@loaded) if @loaded;

    # Auto generate the object on the fly.
    my $id = $rule->value_for_id;
    unless (defined $id) {
        #$DB::single = 1;
        Carp::croak "No id specified for loading members of an infinite set ($class)!"
    }
    my $class_meta = $class->__meta__;
    my @p = (id => $id);
    if (my $alt_ids = $class_meta->{id_by}) {
        if (@$alt_ids == 1) {
            push @p, $alt_ids->[0] => $id;
        }
        else {
            my ($rule, %extra) = UR::BoolExpr->resolve_normalized($class, $rule);
            push @p, $rule->params_list;
        }
    }

    my $obj = $UR::Context::current->_construct_object($class, @p);
    
    if (my $method_name = $class_meta->sub_classification_method_name) {
        my($rule, %extra) = UR::BoolExpr->resolve_normalized($class, $rule);
        my $sub_class_name = $obj->$method_name;
        if ($sub_class_name ne $class) {
            # delegate to the sub-class to create the object
            $UR::Context::current->_abandon_object($obj);
            $obj = $UR::Context::current->_construct_object($sub_class_name,$rule);
            $obj->__signal_change__("load");
            return $obj;
        }
        # fall through if the class names match
    }
    
    $obj->__signal_change__("load");
    return $obj;
}

1;

