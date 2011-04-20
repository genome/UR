package URTAlternate::Person;

use URTAlternate;

class URTAlternate::Person {
    id_by => [
        person_id => { is => 'Integer' },
    ],
    has => [
        name => { is => 'String' },
    ],
    table_name => 'person',
    data_source => 'URTAlternate::DataSource::TheDB',
};

sub uc_name {
    return uc(shift->name);
}

1;
