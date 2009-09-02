package UR::Meta::Class;

our $VERSION = '0.01';

use UR::Moose;
extends( 'Moose::Meta::Class', 'UR::Object' );

sub initialize {
    my $class = shift;
    my $pkg = shift;
    my @metaclasses = (
        'attribute_metaclass' => 'UR::Meta::Attribute',
        'method_metaclass'    => 'UR::Meta::Method',
        'instance_metaclass'  => 'UR::Meta::Instance',
    );

    $class->SUPER::initialize( $pkg, @metaclasses, @_ );
}


#has 'table_name' => (
#    is  => 'rw',
#    isa => 'Str',
#);

#no Moose;
1;

__END__

=head1 NAME

UR::Meta::Class - TODO

=head1 VERSION

This document describes UR::Meta::Class version 0.01

=head1 SYNOPSIS

use UR::Meta::Class;

TODO
  
=head1 DESCRIPTION

TODO

=head1 INTERFACE 

TODO

=head1 METHODS

=over

=item B<initialize>

=back

=head1 DIAGNOSTICS

TODO

=head1 CONFIGURATION AND ENVIRONMENT

TODO

=head1 DEPENDENCIES

UR

=head1 INCOMPATIBILITIES

TODO

=head1 BUGS AND LIMITATIONS

TODO

=head1 AUTHOR

<Todd Hepler>  C<< <<thepler@watson.wustl.edu>> >>


=head1 LICENCE AND COPYRIGHT

Copyright (C) 2007, Washington University in St. Louis

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

