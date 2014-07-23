use strict;
use warnings;
use Test::More tests=> 3;
use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__).'/../..';

use URT;

setup_classes();

subtest 'normal operation' => sub {
    plan tests => 7;
    my $kept = URT::Thing->get(1);
    my $also_kept = URT::Thing->get(related_number => 2);
    do {
        my $unloader = UR::Context::AutoUnloadPool->create();
        URT::Thing->get(98);
        URT::Thing->get(related_number => 2);  # re-get something gotten in the outer scope
        URT::Thing->get(related_number => 99);
    };
    ok(URT::Thing->is_loaded(id => $kept->id), 'URT::Thing is still loaded');
    ok(URT::Thing->is_loaded(id => $also_kept->id), 'other URT::Thing is still loaded');
    ok(URT::Related->is_loaded(id => $also_kept->id), 'URT::Related is still loaded');

    foreach my $id ( 98, 99 ) {
        ok(! URT::Thing->is_loaded(id => $id), "Expected URT::Thing $id was unloaded");
        ok(! URT::Related->is_loaded(id => $id), "Expected URT::Related $id was unloaded");
    }
};

subtest 'exception while unloading' => sub {
    plan tests => 2;

    my $changed_id = 99;
    my $unchanged_id = 98;
    do {
        my $unloader = UR::Context::AutoUnloadPool->create();
        my $thing = URT::Thing->get($changed_id);
        $thing->changable_prop(1000);

        URT::Thing->get($unchanged_id);
    };
    ok(URT::Thing->is_loaded($changed_id), 'Changed object did not get unloaded');
    ok(! URT::Thing->is_loaded($unchanged_id), 'Unchanged object did get unloaded');

};

subtest 'call delete on pool' => sub {
    plan tests => 2;

    my $kept_id = 100;
    do {
        my $unloader = UR::Context::AutoUnloadPool->create();
        URT::Thing->get($kept_id);

        ok($unloader->delete, 'Delete the auto unloader');
    };
    ok(URT::Thing->is_loaded($kept_id), 'Object was not unloaded');
};

sub setup_classes {
    my $generic_loader = sub {
        my($class_name, $rule, $expected_headers) = @_;
        my $value;
        foreach my $prop ( $rule->template->_property_names ) {
            if ($value = $rule->value_for($prop)) {
                last;
            }
        }

        my @value = ($value) x scalar(@$expected_headers);
        return ($expected_headers, [ \@value ]);
    };

    class URT::Related {
        id_by => 'id',
        data_source => 'UR::DataSource::Default',
    };
    *URT::Related::__load__ = $generic_loader;
    
    class URT::Thing {
        id_by => 'id',
        has => [
            changable_prop => { is => 'Number' },
            related => { is => 'URT::Related', id_by => 'id' },
            related_number => { via => 'related', to => 'id' },
        ],
        data_source => 'UR::DataSource::Default',
    };
    *URT::Thing::__load__ = $generic_loader;
}
