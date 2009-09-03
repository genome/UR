package UR::Object::Command::FetchAndDo;

use strict;
use warnings;

use Command;

class UR::Object::Command::FetchAndDo {
    is => 'Command',
    is_abstract => 1,
    has => [
    subject_class => {
        is => 'UR::Object::Type', 
        id_by => 'subject_class_name',
    }, 
    filter => {
        is => 'Text',  
        is_optional => 1,
        doc => 'Filter results based on the parameters.  See below for how to.'
    },
    ], 
};

use Data::Dumper;

########################################################################

sub help_brief {
    return "Fetch objects based on filters and then perform a function on each object";
}

sub help_synopsis {
    return "Fetch objects based on filters and then perform a function on each object";
}

sub help_detail {          
    my $class = shift;

    return $class->_filter_doc;
}

sub _filter_doc {          
    my $class = shift;

    my $doc = <<EOS;
Filtering:
 Create filter equations by combining filterable properties with operators and values.
 Combine and separate these 'equations' by commas.  
 Use single quotes (') to contain values with spaces: name='genome center'
 Use percent signs (%) as wild cards in like (~).

Filterable Properties: 
EOS

    for my $property ( $class->_subject_class_filterable_properties )
    {
        $doc .= sprintf(" %s\n", $property->property_name);
        next;
        $doc .= sprintf(
            " %s: %s\n",
            $property->property_name,
            ( $property->description || 'no doc' ),
        );
    }

    $doc .= <<EOS;

Operators:
 =  (exactly equal to)
 ~  (like the value)
 >  (greater than)
 >= (greater than or equal to)
 <  (less than)
 <= (less than or equal to)

Examples:
 name='genome center'
 employees>200
 name~genome,employees>200

EOS
}

########################################################################

sub execute {  
    my $self = shift;    

    my $iterator = $self->_fetch
        or return;

    return $self->_do($iterator);
}

sub _subject_class_filterable_properties {
    my $self = ( ref $_[0] ) ? $_[0] : $_[0]->create;

    return sort { 
        $a->property_name cmp $b->property_name
    } grep {
        $_->column_name ne ''
    } $self->subject_class->get_all_property_objects;
}

sub _do
{
    shift->error_message("Abstract class.  Please implement a '_do' method in your subclass.");
    return;
}

sub _fetch
{
    my $self = shift;

    my ($bool_expr, %extra) = UR::BoolExpr->create_from_filter_string(
        $self->subject_class_name, 
        $self->filter, 
    );

    $self->error_message( sprintf('Unrecognized field(s): %s', join(', ', keys %extra)) )
        and return if %extra;
    
    return $self->subject_class_name->create_iterator
    (
        where => $bool_expr,
    ); # error happens in object
}

1;

#$HeadURL: svn+ssh://svn/srv/svn/gscpan/perl_modules/trunk/UR/Object/Command/FetchAndDo.pm $
#$Id: FetchAndDo.pm 36254 2008-07-07 20:14:28Z ebelter $#
