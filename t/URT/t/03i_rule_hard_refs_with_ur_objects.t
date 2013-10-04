#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use URT;
use Test::More tests => 37;


# Test the case where UR objects get serialized in a BoolExpr's value
# as FreezeThaw data.  When the objects come back out, the objects need
# to be from the object cache, and not cloned versions of them

use Scalar::Util qw(refaddr);

class URT::Item {
    has => [
        scalar   => { is => 'SCALAR' },
        array    => { is => 'ARRAY' },
        hash     => { is => 'HASH' },
        linked_list => { is => 'LinkedListNode' },
    ]
};

class URT::ListElement {
    has => {
        name => { is => 'String' },
    }
};

my @ELEMENT_NAMES = qw(foo bar baz foo);  # foo is in there twice

is(scalar(create_elements()), scalar(@ELEMENT_NAMES), 'create list elements');

test_arrayref();
test_hashref();
test_self_referential_data();

sub create_elements {
    map { URT::ListElement->get_or_create(name => $_) } @ELEMENT_NAMES;
}

sub test_arrayref {

    my @elements = map { URT::ListElement->get(name => $_) } @ELEMENT_NAMES;
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
    my @elements = map { URT::ListElement->get(name => $_) } @ELEMENT_NAMES;
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

sub test_self_referential_data {
    my @elements = URT::ListElement->get(name => \@ELEMENT_NAMES);

    # make a linked list
    my $linked_list;
    my $last;
    foreach my $element ( @elements ) {
        my $node = {
            element => $element,
            next => undef,
        };

        if ($linked_list) {
            $last->{next} = $node;
        } else {
            $linked_list = $node;
        }
        $last = $node;
    }
    # make the linked list circular
    $last->{next} = $linked_list;

    # Flag an error and exit if unfreezing the rule data goes into deep recursion
    local $SIG{__WARN__} = sub { ok(0, 'deep recursion'); die; };

    my $bx_id;
    {
        my $bx = URT::Item->define_boolexpr(linked_list => $linked_list);
        ok($bx, 'Create boolexpr containing linked_list with UR Objects');

        my $got_list = $bx->value_for('linked_list');
        is(ref($got_list), 'HASH', 'Got back linked list head');

        elements_match(
            [_extract_UR_objects_from_test_linked_list($got_list)],
            \@elements,
        );
        $bx_id = $bx->id;
    }

    # original bx goes out of scope

    {
        my $bx = UR::BoolExpr->get($bx_id);
        ok($bx, 'Retrieve BoolExpr with linked_list by id');

        my $got_list = $bx->value_for('linked_list');
        elements_match(
            [ _extract_UR_objects_from_test_linked_list($got_list) ],
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

sub _extract_UR_objects_from_test_linked_list {
    my $list = shift;

    my %seen;
    my $visit;
    $visit = sub {
        my $node = shift;
        return $seen{$node}++
                ? ()
                : ( $node->{element}, $visit->($node->{next}));
    };

    return $visit->($list);
}


sub elements_match {
    my($got_elements, $elements) = @_;

    is(scalar(@$got_elements), scalar(@$elements), 'Number of elements match');
    for (my $i = 0; $i < @$got_elements; $i++) {
        is(refaddr($got_elements->[$i]), refaddr($elements->[$i]), "Element $i is the same reference");
    }
}

__END__
    

my $item;
my @element_ids;
{
    my @elements = map { URT::ListElement->create(name => $_) } qw(foo bar baz);
    $item = URT::Item->create(array => \@elements);
    ok($item, 'Created Item with an array of subordinate UR objects');

    my $got_elements = $item->array;
    is(ref($got_elements), 'ARARY', 'calling array returns an arrayref');

    my $max = @elements > @$got_elements ? scalar(@elements) : scalar(@$got_elements);
    for (my $i = 0; $i < $max; $i++) {
        is($got_elements->[$i]->id, $elements[$i]->id, "List element $i ID");
        is(refaddr($got_elements->[$i]), refaddr($elements[$i]), "Reference address element $i matches");
    }

    @element_ids = map { $_->id } @elements;
}

# @elements goes out of scope
my @reget_elements = URT::ListElement->get(
