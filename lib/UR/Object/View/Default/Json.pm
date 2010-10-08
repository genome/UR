package UR::Object::View::Default::Json;

use strict;
use warnings;

use JSON;

class UR::Object::View::Default::Json {
    is => 'UR::Object::View::Default::Text',
    has_constant => [
        toolkit     => { value => 'json' },
    ],
    has => [
    ],
};

my $json;
sub _json {
    my ($self) = @_;
    return $json if defined $json;
    return $json = JSON->new->ascii->pretty->allow_nonref;
}

sub _generate_content {
    my $self = shift;

    return $self->_json->encode($self->_jsobj);
}

sub _jsobj {
    my $self = shift;

    my $subject = $self->subject();
    return '' unless $subject;

    my %jsobj = ();
    
#    unless ($self->_subject_is_used_in_an_encompassing_view()) {
        # the content for any given aspect is handled separately
        for my $aspect ($self->aspects) { 
                
            my $val = $self->_generate_content_for_aspect($aspect);
            $jsobj{$aspect->name} = $val if defined $val;
        }
#    }

    return \%jsobj;
}

sub _generate_content_for_aspect {
    my $self = shift;
    my $aspect = shift;

    my $subject = $self->subject;
    my $aspect_name = $aspect->name;

    my $aspect_meta = $self->subject_class_name->__meta__->property($aspect_name);
    warn $aspect_name if ref($subject) =~ /Set/;

    my @value;
    eval {
        @value = $subject->$aspect_name;
    };
    if ($@) {
        warn $@;
        return;
    }
    
    if (@value == 0) {
        return; 
    }
        
    if (Scalar::Util::blessed($value[0])) {
        unless ($aspect->delegate_view) {
            eval {
                $aspect->generate_delegate_view;
            };
            if ($@) {
                warn $@;
            }
        }
    }

    my $ref = [];
 
    # Delegate to a subordinate view if needed.
    # This means we replace the value(s) with their
    # subordinate widget content.
    if (my $delegate_view = $aspect->delegate_view) {
        foreach my $value ( @value ) {
            $delegate_view->subject($value);
            $delegate_view->_update_view_from_subject();
            
            if ($delegate_view->can('_jsobj')) {
                push @$ref, $delegate_view->_jsobj;
            } else {
                my $delegate_text = $delegate_view->content();

                push @$ref, $delegate_text;
            }            
        }
    }
    else {
        for my $value (@value) {
            if (ref($value)) {
                push @$ref, 'ref';  #TODO(ec) make this render references
            } else {
                push @$ref, $value;
            }
        }
    }

    if ($aspect_meta->is_many) {
        return $ref;
    } else {
        return shift @$ref;
    }
}

# Do not return any aspects by default if we're embedded in another view
# The creator of the view will have to specify them manually
sub _resolve_default_aspects {
    my $self = shift;
    unless ($self->parent_view) {
        return $self->SUPER::_resolve_default_aspects;
    }
    return ('id');
}

1;
