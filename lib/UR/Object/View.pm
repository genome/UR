package UR::Object::View;

use warnings;
use strict;
require UR;

our $VERSION = $UR::VERSION;;

class UR::Object::View {
    has_abstract_constant => [
        subject_class_name      => { is_abstract => 1, is_constant => 1 },#is_class_wide => 1, is_constant => 1, is_optional => 0 },           
        perspective             => { is_abstract => 1, is_constant => 1 },#is_class_wide => 1, is_constant => 1, is_optional => 0 },   
        toolkit                 => { is_abstract => 1, is_constant => 1 },#is_class_wide => 1, is_constant => 1, is_optional => 0 },
    ],
    has_optional => [
        subject => { 
                    is => 'UR::Object',  
                    id_class_by => 'subject_class_name', id_by => 'subject_id', 
                    doc => 'the object being observed' 
        },
        aspects => { 
                    is => 'UR::Object::View::Aspect', 
                    reverse_as => 'parent_view',
                    is_many => 1, 
                    specify_by => 'name',
                    order_by => 'number',
                    doc => 'the aspects of the subject this view renders' 
        },
        _widget  => { 
            doc => 'the object/data native to the specified toolkit which does the actual visualization' 
        },
    ],
    has_many_optional => [
        aspect_names    => { via => 'aspects', to => 'name' },
    ]
};

# construction and destruction

sub create {
    my $class = shift;    

    if ($class eq __PACKAGE__) {
        $class = $class->_resolve_view_class_for_params(@_);
    }

    if ($class ne __PACKAGE__) {
        # This is part of a $subclass->SUPER::create() call.  There's
        # nothing to do here except pass the call up the inheritance chain
        return $class->SUPER::create(@_);
    }

    # Otherwise, we're using this as a factory to create the correct viewer subclass 

    my $self = $class->create(@_);
    return unless $self;

    return $self;
}

sub _resolve_view_class_for_params {
    # View modules use standardized naming:  SubjectClassName::View::Perspective::Toolkit.
    # The "SubjectClassName" can be the class name of the subject, or the first ancestor with 
    # a view with the expected perspective/toolkit.
    my $class = shift;
    my %params = $class->define_boolexpr(@_)->params_list;
    
    my $subject_class_name = delete $params{subject_class_name};
    my $perspective = delete $params{perspective};
    my $toolkit = delete $params{toolkit};
    my $aspects = delete $params{aspects};
    
    $perspective = lc($perspective);
    $toolkit = lc($toolkit);
    if (%params) {
        my @params = %params;
        $class->error_message("Bad params: @params");
        return;
    }

    my $namespace = $subject_class_name->__meta__->namespace;
    my $vocabulary = ($namespace and $namespace->can("get_vocabulary") ? $namespace->get_vocabulary() : undef);
    $vocabulary = UR->get_vocabulary;

    my $subject_class_object = $subject_class_name->__meta__;
    my @possible_subject_class_names = ($subject_class_name,$subject_class_name->inheritance);
    
    my $subclass_name;
    for my $possible_subject_class_name (@possible_subject_class_names) {
        $subclass_name = join("::",
            $possible_subject_class_name,
            "View",
            join ("",
                $vocabulary->convert_to_title_case (
                    map { ucfirst(lc($_)) }
                    split(/\s+/,$perspective)
                )
            ),
            join ("",
                $vocabulary->convert_to_title_case (
                    map { ucfirst(lc($_)) }
                    split(/\s+/,$toolkit)
                )
            )
        );
    
        my $subclass_meta = UR::Object::Type->get($subclass_name);
        unless ($subclass_meta) {
            next;
        }
        
        unless($subclass_name->isa(__PACKAGE__)) {
            warn "Subclass $subclass_name exists but is not a view?!";
            next;
        }

        return $subclass_name;
    }

    return;
}

sub _delete_object {
    # This covers the needs of both unload() and delete().
    # Ensure that we clean up after deletion of any kind.
    my $self = shift;
    foreach my $subscription ($self->_subscriptions)
    {
        my ($class, $id, $callback) = @$subscription;
        $class->cancel_change_subscription($id, $callback);
    }    
    return $self->SUPER::_delete_object(@_);
}

# rendering implementation

sub widget {
    my $self = shift;
    if (@_) {
        Carp::confess("widget() is not settable!");
    }
    my $widget = $self->_widget();
    unless ($widget) {
        $widget = $self->_create_widget();
        return unless $widget;
        $self->_widget($widget);
    }
    return $widget;
}

sub _create_widget {
    Carp::confess("The _create_widget method must be implemented for all concrete "
        . " viewer subclasses.  No _create_widget for " 
        . (ref($_[0]) ? ref($_[0]) : $_[0]) . "!");
}

sub _bind_subject {
    my $self = shift;
    my $subject = $self->get_subject();
    my $subscriptions = $self->{subscriptions};

    # See uf we;ve already done this.    
    return 1 if $subscriptions->{$subject};

    # Wipe subscriptions from the last bound subscription(s).
    for (keys %$subscriptions) {
        my $s = delete $subscriptions->{$_};
        my ($class, $id, $method,$callback) = @$s;
        $class->cancel_change_subscription($id, $method,$callback);
    }

    # Make a new subscription for this subject
    my $subscription = $subject->create_subscription(
        callback => sub {
            $self->_update_widget_from_subject(@_);
        }
    );
    $self->{subscriptions}{$subject} = $subscription;
    
    # Set the viewer to show initial data.
    $self->_update_widget_from_subject;
    
    return 1;
}

sub _update_widget_from_subject {
    Carp::confess("The _update_widget_from_subject method must be implemented for all concreate "
        . " viewer subclasses.  No _update_subject_from_widgetfor " 
        . (ref($_[0]) ? ref($_[0]) : $_[0]) . "!");
}

sub _update_subject_from_widget {
    Carp::confess("The _update_widget_from_subject method must be implemented for all concreate "
        . " viewer subclasses.  No _update_subject_from_widgetfor " 
        . (ref($_[0]) ? ref($_[0]) : $_[0]) . "!");
}

# external controls

sub _toolkit_class {
    my $self = shift;
    my $toolkit = $self->toolkit;
    return "UR::Object::View::Toolkit::" . ucfirst(lc($toolkit));
}

sub show {
    my $self = shift;
    $self->_toolkit_class->show_viewer($self);
}

sub show_modal {
    my $self = shift;
    $self->_toolkit_class->show_viewer_modally($self);
}

sub hide {
    my $self = shift;
    $self->_toolkit_class->hide_viewer($self);
}


=pod

=head1 NAME

UR::Object::View - a base class for "views" of UR::Objects

=head1 SYNOPSIS

  $object = Acme::Product->get(1234);

  $view = $object->create_view(
    perspective         => 'inventory history', # defaults to 'default'
    toolkit             => 'XML',              # Gtk, XML, HTML, JSON, defaults to 
  );

  $html = $view->widget;


=head1 USAGE API 

=over 4

=item create

The constructor requires that the subject_class_name, perspective,
and toolkit be set.  Producing a view object does not "render" the view,
just creates an interface for controlling the view.  

The subject can be set later and changed.  The aspects viewed may 
be constant for a given perspective, or mutable.

=item show

For stand-alone viewers, this puts the viewer widget in its a window.  For 
viewers which are part of a larger viewer, this makes the viewer widget
visible in the parent.

=item hide

Makes the viewer invisible.  This means hiding the window, or hiding the viewer
widget in the parent widget for subordinate viewers.

=item show_modal 

This method shows the viewer in a window, and only returns after the window is closed.
It should only be used for viewers which are a full interface capable of closing itself when done.

=item widget

Returns the "widget" which renders the view.  This is built lazily
on demand.  The actual object type depends on the toolkit named above.  
This method might return HTML text, or a Gtk object.  This can be used
directly, and is used internally by show/show_modal.

=item delete

The destructor removes them all from the view of the user.

It also deletes subordinate components, and the related widget if one has been, 
generated.

=back

=head1 CONSTRUCTION PROPERTIES (CONSTANT)

The following three properties are constant for a given view class.  They
determine which class of view to construct, and must be provided to create().

=over 4

=item subject_class_name
    
The class of subject this viewer will view.  Constant for any given viewer,
but this may be any abstract class up-to UR::Object itself.
    
=item perspective

Used to describe the layout logic which gives logical content
to the viewer.

=item toolkit

The specific (typically graphical) toolkit used to construct the UI.
Examples are Gtk, Gkt2, Tk, HTML, XML.

=back

=head1 CONFIGURABLE PROPERTIES

These methods control which object is being viewed, and what properties 
of the object are viewed.  They can be provided at construction time,
or afterward.

=over 4

=item subject

The particular "model" object, in MVC parlance, which is viewed by this view.
This value may change

=item aspects / add_aspect / remove_aspect

Specifications for properties/methods of the subject which are rendered in
the view.  Some views have mutable aspects, while others merely report
which aspects are revealed by the perspective in question.

An "aspect" is some characteristic of the "subject" which is rendered in the 
viewer.  Any property of the subject is usable, as is any method.

=back

=head1 IMPLEMENTATION INTERFACE 

When writing a new view class, the class name is expected to 
follow a formula:

     Acme::Rocket::View::FlightPath::Gtk2
     \          /           \    /      \
     subject class        perspective    toolkit

The toolkit is expected to be a single word.   The perspective
is everything before the toolkit, and after the last 'view' word.
The subject_class_name is everything to the left of the final
'::View::'.

Intermediate classes can be constructed to consolidate logic as 
the developer sees fit.  A module like ::FlightPath::Gtk2 might keep 
most logic in Acme::Rocket::View::FlightPath, and only toolkit specifics in
::Gtk2, but this is not required as long as the module functions.

There are three methods which require an implementation, unless
the developer inherits from a subclass of UR::Object::View which
provides these methods:

=over 4

=item _create_widget

This creates the widget the first time ->widget() is called on a view.

This should be implemented in a given perspective/toolkit module to actually
create the GUI using the appropriate toolkit.  

It will be called before the specific subject is known, so all widget creation 
which is subject-specific should be done in _bind_subject().  As such it typically
only configures skeletal aspects of the view.

=item _bind_subject

This method is called when the subject is set, or when it is changed, or unset.
It updates the widget to reflect changes to the widget due to a change in subject. 

This method has a default implementation which does a general subscription
to changes on the subject.  It probably does not need to be overridden
in custom viewers.  Implementations which _do_ override this should take 
an undef subject, and be sure to un-bind a previously existing subject if 
there is one set. 

=item _update_widget_from_subject

If and when the property values of the subject change, this method will be called on 
all viewers which render the changed aspect of the subject.

=item _update_subject_from_widget

When the widget changes, it should call this method to save the UI changes
to the subject.  This is not applicable to read-only views.

=back

=head1 OTHER METHODS 

=over 4

=item _toolkit_class

This method is useful to provide generic toolkit-based services to a view,
using a toolkit agnostic API.  It can be used in base classes which,
for instance, want to share logic for a given perspective across toolkits.

Returns the name of a class which is derived from UR::Object::Toolkit
which implements certain utility methods for viewers of a given toolkit.

=back

=head1 EXAMPLES

$o = Acme::Product->get(1234);

$v = Acme::Product::View::InventoryHistory::HTML->create();

=cut

