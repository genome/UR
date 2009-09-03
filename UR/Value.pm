package UR::Value;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Value',
    is => ['UR::Object'],
    english_name => 'ur value',
);

sub _load {
    my $class = shift;    
    my $rule = shift;
        
    # See if the requested object is loaded.
    my @loaded = $UR::Context::current->get_objects_for_class_and_rule($class,$rule,0);
    $class->context_return(@loaded) if @loaded;

    # Auto generate the object on the fly.
    unless (defined $rule->specified_value_for_id) {
        $DB::single = 1;
        die "No id specified for loading members of an infinite set ($class)!"
    }
    my $obj = $class->create_object($rule);
    
    my $class_meta = $class->get_class_object;
    if (my $method_name = $class_meta->sub_classification_method_name) {
        my($rule, %extra) = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($class, $rule);
        my $sub_class_name = $obj->$method_name;
        if ($sub_class_name ne $class) {
            # delegate to the sub-class to create the object
            $obj->delete_object();
            $obj = $sub_class_name->create_object($rule);
            $obj->signal_change("load");
            return $obj;
        }
        # fall through if the class names match
    }
    
    $obj->signal_change("load");
    return $obj;
}

1;
