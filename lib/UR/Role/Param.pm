package UR::Role::Param;

use strict;
use warnings;

use Carp qw();
use Scalar::Util qw(blessed);

my %all_params;

sub _constructor {
    my($class, %params) = @_;
    foreach my $param_name ( qw( role_name name varref state ) ) {
        Carp::croak("$param_name is a required param") unless exists $params{$param_name};
    }
    $all_params{$params{role_name}}->{$params{name}} = bless \%params, $class;
}

sub new {
    my $class = shift;
    return $class->_constructor(@_, state => 'unbound');
}
    
sub TIESCALAR {
    my $class = shift;
    return $class->_constructor(@_, state => 'bound');
}

sub name { shift->{name} }
sub role_name { shift->{role_name} }
sub varref { shift->{varref} }
sub state { shift->{state} }

sub FETCH {
    my $self = shift;
    my $param_name = $self->name;

    # show stack
    for (my $f = 0; my @caller = caller($f); $f++) {
        printf("Caller $f: package %s in %s() at %s:%d\n",
                    @caller[0, 3, 1, 2])
    }

    #my($role_name) = caller(1);
    my @caller = caller(1);
    my $role_name = $caller[0];
print "Fetching value for $param_name in $role_name\n";
    my $role_instance = $self->_search_for_invocant_role_instance($role_name);
    unless ($role_instance) {
        Carp::confess("Role param '$param_name' is not bound to a value in this call frame");
    }
    my $params = $role_instance->_get_role_params_for_package($role_name);
    return $params->{$param_name};
}

sub STORE {
    my $self = shift;
    my $name = $self->name;
    Carp::croak("Role param '$name' is read-only");
}

sub _search_for_invocant_role_instance {
    my($self, $role_name) = @_;

    local $@;
    my $role_instance;
    for (my $frame = 1; ; $frame++) {
        my $invocant = do {
            package DB;
            my @caller = caller($frame);
            last unless @caller;
            eval { $DB::args[0] };
        };
        my $invocant_class = blessed($invocant) || (! ref($invocant) && $invocant);
        next unless $invocant_class;

        $role_instance = UR::Role::Instance->get(role_name => $role_name, 'class_name isa' => $invocant_class);
        last if $role_instance;
    }
    return $role_instance;
}

sub param_names_for_role {
    my($class, $role_name) = @_;
    return keys(%{ $all_params{$role_name} });
}

sub replace_unbound_params_in_struct_with_values {
    my($class, $struct, @role_objects) = @_;

    my %role_params = map { $_->role_name => $_->role_params } @role_objects;

    my $replacer = sub {
        my $ref = shift;

        my $self = $$ref;
        my $role_params = $role_params{$self->role_name};
        $$ref = $role_params->{$self->name};  # replaces value in structure

        # replace the role param variable
        my $role_param_ref = $self->varref;
        unless (tied($$role_param_ref)) {
            tie $$role_param_ref, 'UR::Role::Param',
                name => $self->name,
                role_name => $self->role_name,
                varref => $self->varref;
        }
    };

    _visit_params_with_values_in_struct($struct, $replacer);
}

sub _is_unbound_param {
    my $val = shift;
    return (blessed($val) && $val->isa(__PACKAGE__) && $val->state eq 'unbound');
}

sub _visit_params_with_values_in_struct {
    my($struct, $cb) = @_;

    return unless my $reftype = ref($struct);
    if ($reftype eq 'HASH') {
                while(my($key, $val) = each %$struct) {
            if (_is_unbound_param($val)) {
                $cb->(\$struct->{$key});
            } else {
                _visit_params_with_values_in_struct($val, $cb);
            }
        }
    } elsif ($reftype eq 'ARRAY') {
        for(my $i = 0; $i < @$struct; $i++) {
            my $val = $struct->[$i];
            if (_is_unbound_param($val)) {
                $cb->(\$struct->[$i]);
            } else {
                _visit_params_with_values_in_struct($val, $cb);
            }
        }
    } elsif ($reftype eq 'SCALAR') {
        _visit_params_with_values_in_struct($struct, $cb);
    }
}

1;
