#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;
use Test::More tests => 22;

# Test the case where UR objects get serialized in a BoolExpr's value
# as FreezeThaw data.  When the objects come back out, the objects need
# to be from the object cache, and not cloned versions of them

use Scalar::Util qw(refaddr);

class URT::Item {
    has => [
        scalar   => { is => 'SCALAR' },
        array    => { is => 'ARRAY' },
        hash     => { is => 'HASH' }
    ]
};

class URT::ListElement {
    has => {
        name => { is => 'String' },
    }
};

my @ELEMENT_NAMES = qw(foo bar baz);

is(scalar(create_elements()), scalar(@ELEMENT_NAMES), 'create list elements');

#test scalarref();
test_arrayref();
test_hashref();

sub create_elements {
    map { URT::ListElement->create(name => $_) } @ELEMENT_NAMES;
}

sub test_arrayref {

    my @elements = URT::ListElement->get(name => \@ELEMENT_NAMES);
    my $bx_id;
    {
        my $bx = URT::Item->define_boolexpr(array => \@elements);
        ok($bx, 'Create boolexpr comtaining arrayref of UR objects');

        my $got_elements = $bx->value_for('array');
        elements_match($got_elements, \@elements);
        $bx_id = $bx->id;
    }

    # Original bx goes out of scope

    {
        my $bx = UR::BoolExpr->get($bx_id);
        ok($bx, 'Retrieve BoolExpr with arrayref by id');

        my $got_elements = $bx->value_for('array');
        elements_match($got_elements, \@elements);
    }
}

sub test_hashref() {
    my @elements = URT::ListElement->get(name => \@ELEMENT_NAMES);
    my $bx_id;
    {
        # Besides testing a hashref, also test that it will recurse into
        # nested data structures
        my %h = map { $_->name => [ { $_->name => $_ } ] } @elements;
        my $bx = URT::Item->define_boolexpr(hash => \%h);
        ok($bx, 'Create boolexpr containing hashref of UR Objects');

        my $got_elements = $bx->value_for('hash');
        is(ref($got_elements), 'HASH', 'Got back hashref');

        elements_match(
            _extract_UR_objects_from_test_hashref($got_elements),
            \@elements,
        );
        $bx_id = $bx->id;
    }

    # original bx goes out of scope

    {
        my $bx = UR::BoolExpr->get($bx_id);
        ok($bx, 'Retrieve BoolExpr with hashref by id');

        my $got_elements = $bx->value_for('hash');
        elements_match(
            _extract_UR_objects_from_test_hashref($got_elements),
            \@elements,
        );
    }

}

sub _extract_UR_objects_from_test_hashref {
    my $data = shift;

    my @elements;
    foreach my $name ( @ELEMENT_NAMES ) {
        push @elements, $data->{$name}->[0]->{$name};
    }
    return \@elements;
}


sub elements_match {
    my($got_elements, $elements) = @_;

    is(scalar(@$got_elements), scalar(@$elements), 'Number of elements match');
    for (my $i = 0; $i < @$got_elements; $i++) {
        is(refaddr($got_elements->[$i]), refaddr($elements->[$i]), "Element $i is the same reference");
    }
}

