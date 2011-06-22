#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use above 'UR';
use Test::More;

class Base {
    is => 'UR::Object',
    subclass_description_preprocessor => 'Base::_preprocess',
    subclassify_by => 'subclass_name',
};

package Base;
sub _preprocess {
    my ($class, $desc) = @_;
    my $count_prop = $desc->{has}{count};
    $desc->{has}{extra_property} = {
        is => 'Number',
        data_type => 'Number',
        property_name => 'extra_property',
        type_name => $count_prop->{type_name},
        class_name => $count_prop->{class_name},
    };
    return $desc;
}

package main;

eval {
    class Derived {
        is => 'Base',
        has => [
            count => {
                is => 'Number',
            },
        ],
    };
};
ok($@, "specifying redundant/ambiguous properties via preprocessing is an error");

done_testing();
