package UR::Object::View::Identity::Text;

use strict;
use warnings;

class UR::Object::View::Identity::Text {
    is => 'UR::Object::View::Default::Text',
    has_constant => [
        perspective => { value => 'identity' },
        toolkit     => { value => 'text' },
    ],
    has => [
        indent_text => { is => 'Text', default_value => '  ', doc => 'indent child views with this text' },
    ],
};

sub _resolve_default_aspects {
    return;
}

1;

=pod

=head1 NAME

UR::Object::View::Identity::Text - object identity views in text format

=head1 DESCRIPTION

This class implements basic text views of objects.  That has no aspects by default.
 
=head1 SEE ALSO

UR::Object::View, UR::Object::View::Toolkit::Text, UR::Object

=cut

