
=head1 NAME

UR::BoolExpr::And -  A rule which is true if all of its underlying rules are true 

=cut

package UR::BoolExpr::Template::And;

use warnings;
use strict;
our $VERSION = '0.1';

require UR;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    is              => ['UR::BoolExpr::Template'],
);

# These methods work only for legacy rules which are composite, and where the
# logic_type = 'And' and underlying_rule_templates are all PropertyComparison

sub get_underlying_rules_for_values {
    my $self = shift;
    my @values = @_;    
    my @underlying_templates = $self->get_underlying_rule_templates();
    my @underlying_rules;
    for my $template (@underlying_templates) {
        my $n = $template->num_values;
        my $value_id = $template->values_to_value_id(splice(@values,0,$n));
        my $rule_id = UR::BoolExpr->composite_id($template->id,$value_id);
        my $rule = UR::BoolExpr->get($rule_id);
        push @underlying_rules, $rule;
    }
    return @underlying_rules;
}

sub _underlying_keys {
    my $self = shift;
    my $logic_detail = $self->logic_detail;
    return unless $logic_detail;
    my @underlying_keys = split(",",$logic_detail);
    return @underlying_keys;
}

sub get_underlying_rule_templates {
    my $self = shift;
    my @underlying_keys = grep { substr($_,0,1) eq '-' ? () : ($_) } $self->_underlying_keys();
    my $id;
    my $subject_class_name = $self->subject_class_name;
    return map {                
            UR::BoolExpr::Template::PropertyComparison
                ->_get_for_subject_class_name_and_logic_detail(
                    $subject_class_name,
                    $_
                );
        } @underlying_keys;
}

sub specifies_value_for_property_name {
    my ($self, $property_name) = @_;
    Carp::confess() if not defined $property_name;
    my @underlying_templates = $self->get_underlying_rule_templates();        
    return grep { $property_name eq $_->property_name } @underlying_templates;
}

sub evaluate_subject_and_values {
    my $self = shift;
    my $subject = shift;
    if (my @underlying = $self->get_underlying_rule_templates) {
        while (my $underlying = shift (@underlying)) {
            my $value = shift @_;
            unless ($underlying->evaluate_subject_and_values($subject, $value)) {
                return;
            }
        }
    }
    return 1;
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
