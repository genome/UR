package UR::DeletedRef;

use strict;
use warnings;

our $all_objects_deleted = {};
our %burried;

sub bury {
    my $class = shift;

    for my $object (@_) {
        %$object = (original_class => ref($object), original_data => {%$object});
        bless $object, 'UR::DeletedRef';
        my $stringified = $object;
        $all_objects_deleted->{$stringified} = $object;
        Scalar::Util::weaken($all_objects_deleted->{$stringified});
    }

    return 1;
}

sub resurrect {
    shift unless (ref($_[0]));

    foreach my $object (@_) {
        delete $all_objects_deleted->{"$object"};
        bless $object, $object->{original_class};
        %$object = (%{$object->{original_data}});
        $object->resurrect_object if ($object->can('resurrect_object'));
    }

    return 1;
}

use Data::Dumper;

sub AUTOLOAD {
    our $AUTOLOAD;
    my $method = $AUTOLOAD;
    $method =~ s/^.*:://g;
    Carp::confess("Attempt to use a reference to an object which has been deleted with method '$method'\nRessurrect it first.\n" . Dumper($_[0]));
}

sub DESTROY {
    # print "Destroying @_\n";
    delete $all_objects_deleted->{"$_[0]"};
}

1;

