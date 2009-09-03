
=head1 NAME

UR::BoolExpr::Template::PropertyComparison - implements logic for rules with a logic_type of "PropertyComparison" 

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut


package UR::BoolExpr::Template::PropertyComparison;

use warnings;
use strict;
our $VERSION = '0.1';

# Define the class metadata.

require UR;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    is              => ['UR::BoolExpr::Template'],
    #has => [qw/
    #    rule_type        
    #    subject_class_name
    #    property_name
    #    comparison_operator
    #    value
    #    resolution_code_perl
    #    resolution_code_sql
    #/],
    #id_by => ['subject_class_name','logic_string']
);

use UR::BoolExpr::Template::PropertyComparison::Equals;
use UR::BoolExpr::Template::PropertyComparison::LessThan;
use UR::BoolExpr::Template::PropertyComparison::In;
use UR::BoolExpr::Template::PropertyComparison::Like;

sub property_name {
    (split(' ',$_[0]->logic_detail))[0]
}

sub comparison_operator {
    (split(' ',$_[0]->logic_detail))[1]
}

sub get_underlying_rules_for_values {
    return;
}

sub num_values {
    # Not strictly correct...
    return 1;
}

sub evaluate_subject_and_values {
    $DB::single = 1;
    my $self = shift;
    my $subject = shift;
    Carp::confess(
        "Failed to implement evaluate_subject_and_values() for '"
        . $self->comparison_operator
        . "' !\n"
        . "Add the method to ". $self->class . ".\n"        
    );
}

our %subclass_suffix_for_builtin_symbolic_operator = (
    '='     => "Equals",
    '<'     => "LessThan",
    '>'     => "GreaterThan",    
    '[]'    => "In",
    '!='    => "NotEqual",
    'ne'    => "NotEqual",
    '<='    => 'LessOrEqual',
    '>='    => 'GreaterOrEqual',
);

sub resolve_subclass_for_comparison_operator {
    my $class = shift;
    my $comparison_operator = shift;

    # Remove any escape sequence that may have been put in at UR::BoolExpr::resolve_for_class_and_params()
    $comparison_operator =~ s/-.+$// if $comparison_operator;
    
    my $subclass_name;
    
    if (!defined($comparison_operator)) {
        $subclass_name = $class . '::Equals';
    }    
    else {
        $comparison_operator = lc($comparison_operator);
        my $suffix;
        my $not;
        unless ($suffix = $subclass_suffix_for_builtin_symbolic_operator{$comparison_operator}) {
            my $core_comparison_operator;
            if ($comparison_operator =~ /not (.*)/) {
                $not = 1;
                $core_comparison_operator = $1;
            }
            else {
                $not = 0;
                $core_comparison_operator = $comparison_operator;
            }

            $suffix = ucfirst(lc($core_comparison_operator));
        }
        $subclass_name = $class . '::' . ($not ? 'Not' : '') . $suffix;
        
        my $subclass_meta = UR::Object::Type->get($subclass_name);
        unless ($subclass_meta) {
            Carp::confess("Unknown operator $comparison_operator");
        }
    }
    
    return $subclass_name;
}

sub _get_for_subject_class_name_and_logic_detail {
    my $class = shift;
    my $subject_class_name = shift;
    my $logic_detail = shift;
    
    my ($property_name, $comparison_operator) = split(' ',$logic_detail, 2);    
    my $subclass_name = $class->resolve_subclass_for_comparison_operator($comparison_operator);    
    my $id = $subclass_name->_resolve_composite_id($subject_class_name, 'PropertyComparison', $logic_detail);
    
    return $subclass_name->get_or_create($id);
}

1;

=pod

=head1 PROPERTIES

=over 4

=item

=back

=head1 GENERAL METHODS

=over 4

=item 

=back

=head1 OBJECT-BASED MEMBERSHIP METHODS

=over 4

Report bugs to <software@watson.wustl.edu>.

=head1 SEE ALSO

App(3), UR::Object(3), UR::BoolExpr::DefinitionType::Manual(3),

=head1 AUTHOR

Scott Smith <ssmith@watson.wustl.edu>,

=cut


=cut


# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software.  You may distribute under the terms
# of either the GNU General Public License or the Artistic License, as
# specified in the Perl README file.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

# $Header: /var/lib/cvs/perl_modules/App/Object/Set.pm,v 1.8 2005/07/07 22:07:24 ssmith Exp $
