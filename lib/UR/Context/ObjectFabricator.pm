package UR::Context::ObjectFabricator;

use strict;
use warnings;

use Scalar::Util;
use UR::Context;

# A helper package for UR::Context to keep track about 
# These are normal Perl objects, not UR objects, so they get 
# regular refcounting and scoping


my %all_object_fabricators;

sub create {
    my $class = shift;

    my %params = @_;

    unless ($params{'fabricator'} and ref($params{'fabricator'}) eq 'CODE') {
        Carp::croak("UR::Context::ObjectFabricator::create requires a subroutine ref for the 'fabricator' parameter");
    }

    unless ($params{'context'} and ref($params{'context'}) and $params{'context'}->isa('UR::Context')) {
        Carp::croak("UR::Context::ObjectFabricator::create requires a UR::Context object for the 'context' parameter");
    }

    my $self = bless {}, $class;

    $self->{'fabricator'} = $params{'fabricator'};
    $self->{'context'} = $params{'context'};

    $self->{'all_params_loaded'} = $params{'all_params_loaded'} || {};
    $self->{'in_clause_values'} = $params{'in_clause_values'} || [];

    $all_object_fabricators{$self} = $self;
    Scalar::Util::weaken($all_object_fabricators{$self});

    return $self;
}

sub all_object_fabricators {
    #my @fabricators;
    #my @delete;
    #foreach my $key ( keys %all_object_fabricators ) {
    #    if ($all_object_fabricators{$key}) {
    #        push @fabricators, $all_object_fabricators{$key};
    #    } else {
    #        push @delete, $key;
    #    }
    #}
    #delete @all_object_fabricators{@delete};
    #return @fabricators;
    return values %all_object_fabricators;
}

# simple accessors

sub fabricator {
    my $self = shift;
    return $self->{'fabricator'};
}

sub context {
   my $self = shift;
   return $self->{'context'};
}

sub all_params_loaded {
    my $self = shift;
    return $self->{'all_params_loaded'};
}

sub in_clause_values {
    my $self = shift;
    return $self->{'in_clause_values'};
}

# call the object fabricator closure
sub fabricate {
    my $self = shift;

    &{$self->{'fabricator'}};
}

# Returns true if this fabricator has loaded an object matching this boolexpr
sub is_loading_in_progress_for_boolexpr {
    my $self = shift;
    my $boolexpr = shift;

    my $template_id = $boolexpr->template_id;
    # FIXME should it use is_subsest_of here?
    return unless exists $self->{'all_params_loaded'}->{$template_id};
    return unless exists $self->{'all_params_loaded'}->{$template_id}->{$boolexpr->id};
    return 1;
}


# UR::Contect::_abandon_object calls this to forget about loading an object
sub delete_from_all_params_loaded {
    my($self,$template_id,$boolexpr_id) = @_;

    return unless ($template_id and $boolexpr_id);

    my $all_params_loaded = $self->all_params_loaded;

    return unless $all_params_loaded;
    return unless exists($all_params_loaded->{$template_id});
    delete $all_params_loaded->{$template_id}->{$boolexpr_id};
}


sub finalize {
    my $self = shift;

    my $local_all_params_loaded = $self->{'all_params_loaded'};

    foreach my $template_id ( keys %$local_all_params_loaded ) {
        while(1) {
            my($rule_id,$val) = each %{$local_all_params_loaded->{$template_id}};
            last unless defined $rule_id;
            next unless exists $UR::Context::all_params_loaded->{$template_id}->{$rule_id};  # Has unload() removed this one earlier?
            $UR::Context::all_params_loaded->{$template_id}->{$rule_id} += $val;
        }
    }

    # Anything left in here is in-clause values that matched nothing.  Make a note in
    # all_params_loaded showing that so later queries for those values won't hit the 
    # data source
    my $in_clause_values = $self->in_clause_values;
    foreach my $property ( keys %$in_clause_values ) {
        while (my($value, $data) = each %{$in_clause_values->{$property}} ) {
            $UR::Context::all_params_loaded->{$data->[0]}->{$data->[1]} = 0;
        }   
    }   

    delete $all_object_fabricators{$self};
    $self->{'all_params_loaded'} = undef;
}   


sub DESTROY {
    my $self = shift;
    # Don't apply the changes.  Maybe the importer closure just went out of scope before
    # it read all the data
    my $local_all_params_loaded = $self->{'all_params_loaded'};
    if ($local_all_params_loaded) {
        # finalize wasn't called on this iterator; maybe the importer closure went out
        # of scope before it read all the data.
        # Conditionally apply the changes from the local all_params_loaded.  If the Context's
        # all_params_loaded is defined, then another query has successfully run to
        # completion, and we should add our data to it.  Otherwise, we're the only query like
        # this and all_params_loaded should be cleaned out
        foreach my $template_id ( keys %$local_all_params_loaded ) {
            next if ($template_id eq '__in_clause_values__');
            while(1) {
                my($rule_id, $val) = each %{$local_all_params_loaded->{$template_id}};
                last unless $rule_id;
                if (defined $UR::Context::all_params_loaded->{$template_id}->{$rule_id}) {
                    $UR::Context::all_params_loaded->{$template_id}->{$rule_id} += $val;
                } else {
                    delete $UR::Context::all_params_loaded->{$template_id}->{$rule_id};
                }
            }
        }
    }
    delete $all_object_fabricators{$self};
}

1;
