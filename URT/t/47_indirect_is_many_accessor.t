use above 'UR';

use Test::More;
plan tests => 8;

# Cheat, and make it less strict about checking class relationships
#$UR::Object::Type::bootstrapping=1;

UR::Object::Type->define(
    class_name => 'URT::Param',
    id_by => [
        thing_id => { is => 'Number' },
        name => { is => 'String' },
        value => { is => 'String'},
    ],
    has => [
        thing => { data_type => 'URT::Thing', id_by => 'thing_id' },
    ],
);
UR::Object::Type->define(
    class_name => 'URT::Thing',
    id_by => [
        'thing_id' => { is => 'Number' },
    ],
    has => [
        params => { is => 'URT::Param', reverse_id_by => 'thing', is_many => 1 },
        param_values => { via => 'params', to => 'value', is_many => 1, is_mutable => 1 },
        interesting_params => { is => 'URT::Param', reverse_id_by => 'thing', is_many => 1,
                                where => [name => 'interesting']},
        # Actually, either of these property definitions will work
        #interesting_param_values => { via => 'params', to => 'value', is_many => 1, is_mutable => 1,
        #                              where => [ name => 'interesting'] },
        interesting_param_values => { via => 'interesting_params', to => 'value', is_many => 1, is_mutable => 1 },
    ],
);

# complete the above class definitions
#&UR::Object::Type::initialize_bootstrap_classes();


my $o = URT::Thing->create(thing_id => 2, interesting_param_values => ['abc','def']);
ok($o, 'Created another Thing');
my @params = $o->interesting_params;
is(scalar(@params), 2, 'And it has 2 attached interesting params');
isa_ok($params[0], 'URT::Param');
isa_ok($params[1], 'URT::Param');

@params = sort { $a->value cmp $b->value } @params;
is($params[0]->name, 'interesting', "param 1's name is interesting");
is($params[1]->name, 'interesting', "param 2's name is interesting");

is($params[0]->value, 'abc', "param 1's value is correct");
is($params[1]->value, 'def', "param 2's value is correct");

