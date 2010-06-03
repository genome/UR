
package UR::Object::Set::View::Default::Xml;

use strict;
use warnings;

class UR::Object::Set::View::Default::Xml {
    is => 'UR::Object::View::Default::Xml',
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
