package UR::Object::Iterator;

use strict;
use warnings;

# These are no longer UR Objects.  They're regular blessed references that
# get garbage collected in the regular ways

#use UR;
#
#UR::Object::Type->define(
#    class_name      => __PACKAGE__,
#    has => [
#        filter_rule_id          => {},
#    ],
#);
#
#sub create_for_filter_rule {
#    my $class = shift;
#    my $filter_rule = shift;
#    my $code = $UR::Context::current->get_objects_for_class_and_rule($filter_rule->subject_class_name,$filter_rule,undef,1);
#    
#    my $self = $class->SUPER::create(
#        # TODO: some bug with frozen items?
#        filter_rule_id      => $filter_rule->id,        
#    );
#    
#    $self->_iteration_closure($code);    
#    return $self;
#}

sub create {
    die "Don't call UR::Object::Iterator->create(), use create_for_filter_rule() instead";
}

sub create_for_filter_rule {
    my $class = shift;
    my $filter_rule = shift;
   

    my $code = $UR::Context::current->get_objects_for_class_and_rule($filter_rule->subject_class_name,$filter_rule,undef,1);
    
    my $self = bless { filter_rule_id => $filter_rule->id,
                       _iteration_closure => $code},
               __PACKAGE__;
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

