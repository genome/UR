use UR;
use Test::More tests => 2;

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

    
