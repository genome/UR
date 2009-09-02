
package UR::Object::Iterator;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    has => [
        filter_rule_id          => {},
    ],
);

sub create_for_filter_rule {
    my $class = shift;
    my $filter_rule = shift;
    my $code = $UR::Context::current->get_objects_for_class_and_rule($class,$filter_rule,undef,1);
    
    my $self = $class->SUPER::create(
        # TODO: some bug with frozen items?
        #filter_rule_id      => $filter_rule->id,        
    );
    
    $self->_iteration_closure($code);    
    return $self;
}

sub _iteration_closure {
    my $self = shift;
    if (@_) {
        return $self->{_iteration_closure} = shift;
    }
    $self->{_iteration_closure};
}


sub next {
    shift->{_iteration_closure}->(@_);
}


1;

