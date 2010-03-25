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
        parent_view => {
            is => 'UR::Object::View',
            id_by => 'parent_view_id',
            doc => 'when nested inside another view, this references that view',
        },
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
    ],
    has_optional_transient => [
        _widget  => { 

            doc => 'the object native to the specified toolkit which does the actual visualization' 
        },
        _observer_data => {
            is_transient => 1,
            doc => '  hooks around the subject which monitor it for changes'
        }
    ],
    has_many_optional => [
        aspect_names    => { via => 'aspects', to => 'name' },
    ]
};

sub create {
    my $class = shift;    

    my ($params,@extra) = $class->define_boolexpr(@_);
    
    # set values not specified in the params which can be inferred from the class name
    my ($expected_class,$expected_perspective,$expected_toolkit) = ($class =~ /^(.*)::View::(.*?)::([^\:]+)$/);
    unless ($params->specifies_value_for('subject_class_name')) {
        $params = $params->add_filter(subject_class_name => $expected_class);
    }
    unless ($params->specifies_value_for('perspective')) {
        $params = $params->add_filter(perspective => $expected_perspective);
    }
    unless ($params->specifies_value_for('toolkit')) {
        $params = $params->add_filter(toolkit => $expected_toolkit);
    }

    # now go the other way, and use both to infer a final class name
    $expected_class = $class->_resolve_view_class_for_params($params);
    unless ($expected_class) {
        die "Failed to resolve a subclass for " . __PACKAGE__ 
        . " from parameters.  Expected subject_class_name, perspective,"
        . " and toolkit to be part of the parameters, or class definition.  "
        . "Received $params."
    }

    unless ($class->isa($expected_class)) {
        return $expected_class->create(@_);
    }

    my $self = $expected_class->SUPER::create($params);
    return unless $self;

    $class = ref($self);
    $expected_class = $class->_resolve_view_class_for_params(
        subject_class_name  => $self->subject_class_name,
        perspective         => $self->perspective,
        toolkit             => $self->toolkit
    );
    unless ($expected_class and $expected_class eq $class) {
        $expected_class ||= '<uncertain>';
        die "constructed a $class object but properties indicate $expected_class should have been created.";
    }

    unless ($params->specifies_value_for('aspects')) {
        my @aspect_specs = $self->_resolve_default_aspects();
        for my $aspect_spec (@aspect_specs) {
            my $aspect = $self->add_aspect(ref($aspect_spec) ? %$aspect_spec : $aspect_spec);
            unless ($aspect) {
                $self->error_message("Failed to add aspect @$aspect_spec to new view " . $self->id);
                $self->delete;
                return;
            }
        }
    }

    return $self;
}

sub _resolve_view_class_for_params {
    # View modules use standardized naming:  SubjectClassName::View::Perspective::Toolkit.
    # The subject must be explicitly of class "SubjectClassName" or some subclass of it.
    my $class = shift;
    my %params = $class->define_boolexpr(@_)->params_list;
   
    my $subject_class_name = delete $params{subject_class_name};
    my $perspective = delete $params{perspective};
    my $toolkit = delete $params{toolkit};
    my $aspects = delete $params{aspects};
   
    unless($subject_class_name and $perspective and $toolkit) {
        Carp::confess("Bad params @_.  Expected subject_class_name, perspective, toolkit.");
    }

    $perspective = lc($perspective);
    $toolkit = lc($toolkit);

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

sub _resolve_default_aspects {
    my $self = shift;
    my $parent_view = $self->parent_view;
    my $subject_class_name = $self->subject_class_name;
    my $meta = $subject_class_name->__meta__;
    my @c = ($meta->class_name, $meta->ancestry_class_names);
    my %aspects =  
        map { $_->property_name => 1 }
        grep { not $_->implied_by }
        UR::Object::Property->get(class_name => \@c);
    my @aspects = sort keys %aspects;
    return @aspects;
}

sub __signal_change__ {
    # ensure that changes to the view which occur 
    # after the widget is produced
    # are reflected in the widget
    my ($self,$method,@details) = @_;
    if ($self->_widget) {
        if ($method eq 'subject' or $method =~ 'aspects') {
            $self->_bind_subject();
        }
        elsif ($method eq 'delete') {
            my $observer_data = $self->_observer_data;
            for my $subscription (values %$observer_data) {
                my ($class, $id, $callback) = @$subscription;
                $class->cancel_change_subscription($id, $callback);
            }
            $self->_widget(undef);
        }
    }
    return 1;
}

# rendering implementation

sub widget {
    my $self = shift;
    if (@_) {
        Carp::confess("Widget() is not settable!  Its value is set from _create_widget() upon first use.");
    }
    my $widget = $self->_widget();
    unless ($widget) {
        $widget = $self->_create_widget();
        return unless $widget;
        $self->_widget($widget);
        $self->_bind_subject(); # works even if subject is undef
    }
    return $widget;
}

sub _create_widget {
    Carp::confess("The _create_widget method must be implemented for all concrete "
        . " viewer subclasses.  No _create_widget for " 
        . (ref($_[0]) ? ref($_[0]) : $_[0]) . "!");
}

sub _bind_subject {
    # This is called whenever the subject changes, or when the widget is first created.
    # It handles the case in which the subject is undef.
    my $self = shift;
    my $subject = $self->subject();
    return unless defined $subject;

    my $observer_data = $self->_observer_data;

    # See if we've already done this.    
    return 1 if $observer_data->{$subject};

    # Wipe subscriptions from the last bound subscription(s).
    for (keys %$observer_data) {
        my $s = delete $observer_data->{$_};
        my ($class, $id, $method,$callback) = @$s;
        $class->cancel_change_subscription($id, $method,$callback);
    }

    # Make a new subscription for this subject
    my $subscription = $subject->create_subscription(
        callback => sub {
            $self->_update_view_from_subject(@_);
        }
    );
    $observer_data->{$subject} = $subscription;
    
    # Set the viewer to show initial data.
    $self->_update_view_from_subject;
    
    return 1;
}

sub _update_view_from_subject {
    # This is called whenever the view changes, or the subject changes.
    # It passes the change(s) along, so that the update can be targeted, if the developer chooses.
    Carp::confess("The _update_view_from_subject method must be implemented for all concreate "
        . " viewer subclasses.  No _update_subject_from_viewfor " 
        . (ref($_[0]) ? ref($_[0]) : $_[0]) . "!");
}

sub _update_subject_from_view {
    Carp::confess("The _update_subject_from_view method must be implemented for all concreate "
        . " viewer subclasses.  No _update_subject_from_viewfor " 
        . (ref($_[0]) ? ref($_[0]) : $_[0]) . "!");
}

# external controls

sub show {
    my $self = shift;
    $self->_toolkit_package->show_viewer($self);
}

sub show_modal {
    my $self = shift;
    $self->_toolkit_package->show_viewer_modally($self);
}

sub hide {
    my $self = shift;
    $self->_toolkit_package->hide_viewer($self);
}

sub _toolkit_package {
    my $self = shift;
    my $toolkit = $self->toolkit;
    return "UR::Object::View::Toolkit::" . ucfirst(lc($toolkit));
}


=pod

=head1 NAME

UR::Object::View - a base class for "views" of UR::Objects

=head1 SYNOPSIS

  $object = Acme::Product->get(1234);

  ## Acme::Product::View::InventoryHistory::Gtk2

  $view = $object->create_view(
    perspective         => 'inventory history',
    toolkit             => 'gtk2',              
  );
  $widget = $view->widget();    # returns the Gtk2::Widget itself directly
  $view->show();                # puts the widget in a Gtk2::Window and shows everything
  
  ##

  $view = $object->create_view(
    perspective         => 'inventory history',
    toolkit             => 'xml',              
  );
  $widget = $view->widget();    # returns an arrayref with the xml string reference, and the output filehandle (stdout) 
  $view->show();                # prints the current xml content to the handle
  
  $xml = $view->content();     # returns the XML directly
  
  ##
  
  $view = $object->create_view(
    perspective         => 'inventory history',
    toolkit             => 'html',              
  );
  $widget = $view->widget();    # returns an arrayref with the html string reference, and the output filehandle (stdout) 
  $view->show();                # prints the html content to the handle
  
  $html = $view->content();     # returns the HTML text directly


=head1 USAGE API 

=over 4

=item create

The constructor requires that the subject_class_name, perspective,
and toolkit be set.  Most concrete subclasses have perspective and toolkit 
set as constant.

Producing a view object does not "render" the view, just creates an 
interface for controlling the view, including encapsualting its creation.  

The subject can be set later and changed.  The aspects viewed may 
be constant for a given perspective, or mutable, depending on how
flexible the of the perspective logic is.

=item show

For stand-alone viewers, this puts the viewer widget in its a window.  For 
viewers which are part of a larger viewer, this makes the viewer widget
visible in the parent.

=item hide

Makes the viewer invisible.  This means hiding the window, or hiding the viewer
widget in the parent widget for subordinate viewers.

=item show_modal 

This method shows the viewer in a window, and only returns after the window is closed.
It should only be used for viewers which are a full interface capable of closing itself 
when done.

=item widget

Returns the "widget" which renders the view.  This is built lazily
on demand.  The actual object type depends on the toolkit named above.  
This method might return HTML text, or a Gtk object.  This can be used
directly, and is used internally by show/show_modal.

(Note: see UR::Object::View::Toolkit::Text for details on the "text" widget,
used by HTML/XML views, etc.  This is just the content and an I/O handle to 
which it should stream.)

=item delete

Delete the view (along with the widget(s) and infrastructure underlying it).

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

When writing new view logic, the class name is expected to 
follow a formula:

     Acme::Rocket::View::FlightPath::Gtk2
     \          /           \    /      \
     subject class name    perspective  toolkit

The toolkit is expected to be a single word.   The perspective
is everything before the toolkit, and after the last 'View' word.
The subject_class_name is everything to the left of the final
'::View::'.

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

=item _update_view_from_subject

If and when the property values of the subject change, this method will be called on 
all viewers which render the changed aspect of the subject.

=item _update_subject_from_view

When the widget changes, it should call this method to save the UI changes
to the subject.  This is not applicable to read-only views.

=back

=head1 OTHER METHODS 

=over 4

=item _toolkit_package

This method is useful to provide generic toolkit-based services to a view,
using a toolkit agnostic API.  It can be used in abstract classes which,
for instance, want to share logic for a given perspective across toolkits.

The toolkit class related to a view is responsible for handling show/hide logic,
etc. in the base UR::Object::View class.

Returns the name of a class which is derived from UR::Object::View::Toolkit
which implements certain utility methods for viewers of a given toolkit.

=back

=head1 EXAMPLES

$o = Acme::Product->get(1234);

$v = Acme::Product::View::InventoryHistory::HTML->create();
$v->add_aspect('outstanding_orders');
$v->show;

=cut

