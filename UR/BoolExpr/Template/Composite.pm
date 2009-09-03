package UR::BoolExpr::Template::Composite;

use warnings;
use strict;
our $VERSION = $UR::VERSION;;

require UR;

UR::Object::Type->define(
    class_name  => __PACKAGE__,
    is          => ['UR::BoolExpr::Template'],
);



1;

=pod

=head1 NAME

UR::BoolExpr::Composite - A rule made up of other rules

=head1 SYNOPSIS

@r = $r->get_underlying_rules();
for (@r) {
    print $r->evaluate($c1);
}

=head1 DESCRIPTION

=head1 SEE ALSO

UR::Object(3), UR::BoolExpr::DefinitionType::Manual(3),

=cut
