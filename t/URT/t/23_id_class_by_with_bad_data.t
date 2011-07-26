use UR;
use Test::More tests => 2;

# This test is to reproduce a poor error message that was received
# when trying to access an indirect object which contained an invalid
# class name. In the previous case this simply died to trying to call
# __meta__ on an undefined value within the accessor sub of
# mk_id_based_object_accessor.

class TestClass {
    has => [
        other_class => { is => 'Text' },
        other_id => { is => 'Number' },
        other => { is => 'UR::Object', id_class_by => 'other_class', id_by => 'other_id'},
   ],
};


my $a = TestClass->create(other_class => 'NonExistent', other_id => '1234');

my $other = eval { $a->other };

ok(! $other, 'Calling id_class_by accessor with bad data threw exception');
like($@,
    qr(Can't resolve value for 'other' on class TestClass id),
    'Exception looks ok');

    
