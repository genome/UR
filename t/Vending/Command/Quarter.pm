package Vending::Command::Quarter;

class Vending::Command::Quarter {
    is => 'Vending::Command::InsertMoney',
    has => [
        name => { is_constant => 1, value => 'quarter' },
    ],
    doc => 'Insert a quarter into the machine',
};

1;

