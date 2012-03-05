package UR::Value::CamelCase;

use strict;
use warnings;

require UR;
our $VERSION = "0.37"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::CamelCase',
    is => ['UR::Value::Text'],
);

sub to_text {
    my $self = shift;
    # Split on the first capital or the start of a number
    my @words = split( /(?=(?<![A-Z])[A-Z])|(?=(?<!\d)\d)/, $self->id);
    # Default join is a space
    my $join = ( defined $_[0] ) ? $_[0] : ' '; 
    return UR::Value::Text->get( join($join, map { lc } @words) );
}

1;

