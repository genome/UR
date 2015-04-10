package UR::AttributeHandlers;

use strict;
use warnings;
use attributes;

our @CARP_NOT = qw(UR::Namespace);

# implement's UR's mechanism for sub/variable attributes.
my %support_functions = (
    MODIFY_CODE_ATTRIBUTES => \&modify_attributes,
    FETCH_CODE_ATTRIBUTES => \&fetch_attributes,
);

sub import_support_functions_to_package {
    my $package = shift;

    while( my($name, $code) = each %support_functions ) {
        my $target = join('::', $package, $name);
        do {
            no strict 'refs';
            *$target = $code;
        };
    }
}


my %modify_attribute_handlers = (
    CODE => { overrides => \&modify_code_overrides },
);
my %fetch_attribute_handlers = (
    CODE => { overrides => \&fetch_code_overrides },
);

sub _modify_attribute_handler {
    my($ref, $attr) = @_;
    my $reftype = attributes::reftype($ref);
    return (exists($modify_attribute_handlers{$reftype}) and $modify_attribute_handlers{$reftype}->{$attr});
}

sub _fetch_attribute_handler {
    my($ref, $attr) = @_;
    my $reftype = attributes::reftype($ref);
    return (exists($fetch_attribute_handlers{$reftype}) and $fetch_attribute_handlers{$reftype}->{$attr});
}

sub _decompose_attr {
    my($raw_attr) = @_;
    my($attr, $params_str) = $raw_attr =~ m/^(\w+)(?:\((.*)\))$/;
    my @params = split(/\s*,\s*/, $params_str);
    return ($attr, @params);
}

sub modify_attributes {
    my($package, $ref, @raw_attrs) = @_;

    my @not_recognized;
    foreach my $raw_attr ( @raw_attrs ) {
        my($attr, @params) = _decompose_attr($raw_attr);
        if (my $handler = _modify_attribute_handler($ref, $attr)) {
            $handler->($package, $ref, $attr, @params);
        } else {
            push @not_recognized, $raw_attr;
        }
    }

    return @not_recognized;
}

my %stored_attributes;

sub fetch_attributes {
    my($package, $ref) = @_;

    my $reftype = attributes::reftype($ref);
    my @attrs;
    foreach my $attr ( keys %{ $stored_attributes{$ref} } ) {
        if (my $handler = _fetch_attribute_handler($ref, $attr)) {
            push @attrs, $handler->($package, $ref);
        }
    }
    return @attrs;
}

sub modify_code_overrides {
    my($package, $coderef, $attr, @params) = @_;

    my $list = $stored_attributes{$coderef}->{overrides} ||= [];
    push @$list, @params;
}

sub fetch_code_overrides {
    my($package, $coderef) = @_;

    return sprintf('overrides(%s)',
                    join(', ', @{ $stored_attributes{$coderef}->{overrides} }));
}

1;
