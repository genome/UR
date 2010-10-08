
package UR::Object::Set::View::Default::Json;

use strict;
use warnings;

class UR::Object::Set::View::Default::Json {
    is => 'UR::Object::View::Default::Json',
    has_constant => [
        default_aspects => {
            value => [
                'rule_display',
                'members'
            ]
        }
    ]
};

1;
