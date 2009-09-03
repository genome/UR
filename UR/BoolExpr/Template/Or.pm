
=head1 NAME

UR::BoolExpr::Or - A rule which is true if any of a list of alternative rules are true

=head1 SYNOPSIS

=cut


package UR::BoolExpr::Template::Or;

use warnings;
use strict;
our $VERSION = '0.1';

require UR;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    is              => ['UR::BoolExpr::Template'],    
);


1;

=pod

=head1 SEE ALSO

UR::Object(3), UR::BoolExpr::DefinitionType::Manual(3),

=cut
