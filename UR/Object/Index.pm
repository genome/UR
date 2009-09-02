# Index for app objects.
# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package UR::Object::Index;
our $VERSION = '0.1';
use base qw(UR::Object);

use strict;
use warnings;


# wrapper for one of the ID properties to make it less ugly

    sub indexed_property_names
    {
        no warnings;
        return split(/,/,$_[0]->{indexed_property_string});
    }

# the only non-id property has an accessor...

    sub data_tree
    {
        if (@_ > 1)
        {
            my $old = $_[0]->{data_tree};
            my $new = $_[1];
            if ($old ne $new)
            {
                $_[0]->{data_tree} = $new;
                $_[0]->signal_change('data_tree', $old, $new);
            }
            return $new;
        }
        return $_[0]->{data_tree};
    }

# override create to initilize the index

    sub create {
        my $class = shift;
        my $params = $class->preprocess_params(@_);
        
        $params->{data_tree} ||= {};
        
        my $self = $class->create_object($params);        
        return unless $self;
        
        $self->_build_data_tree;
        $self->_setup_change_subscription;
        
        $self->signal_change("create");        
        return $self;
    }

# this does a lookup as efficiently as possible

    sub get_objects_matching
    {
        # The hash access below generates warnings
        # where undef is a value.  Igore these.
        no warnings;
        
        my @hr = (shift->{data_tree});
        my $value;
        for $value (@_)
        {               
            if (not ref($value))
            {
                # property => value
                @hr = grep { $_ } map { $_->{$value} } @hr;
            }           
            elsif (ref($value) eq "ARRAY") 
            {
                # property => [ v1, v2, v3]
                @hr = grep { $_ } map { @$_{@$value} } @hr;
            } 
            elsif(ref($value) eq "HASH") 
            {
                # property => { operator => "not like", value => "H~_WGS%", escape "~" }
                if (my $op = $value->{operator})
                {
                    if ($op =~ /^(not |)like$/i) 
                    {
                        my $not = $1;
                        my $comparison_value = $value->{value};                        
                        my $escape = $value->{escape};
                        
                        my $regex = 
                            UR::BoolExpr::Template::PropertyComparison::Like->
                                comparison_value_and_escape_character_to_regex(
                                    $comparison_value,
                                    $escape
                                );
                        
                        my @thr;
                        if ($not)
                        {
                            # Get the values using the regular or negative match op.
                            foreach my $h (@hr) {
                                foreach my $k (sort keys %$h) {
                                    if($k !~ /$regex/) {
                                        push @thr, $h->{$k};
                                    }
                                }
                            }
                        }
                        else
                        {
                            # Standard positive match
                            for my $h (@hr) {
                                for my $k (sort keys %$h) {
                                    if ($k =~ /$regex/) {
                                        push @thr, $h->{$k};
                                    }
                                }
                            }
                        }
                        @hr = grep { $_ } @thr;
                    } 
                    elsif ($op =~ /^in$/i)
                    {                
                        $value = $value->{value};
                        my @value = grep { length($_) > 0 } @$value;
                        @hr = grep { $_ } map { @$_{@value} } @hr;
                    }
                    elsif ($op =~ /^not in$/i)
                    {                
                        $value = $value->{value};
                        
                        # make a hash if we got an array as a value
                        #die ">@$value<" if ref($value) eq "ARRAY";
                        $value = { map { $_ => 1 } @$value } if ref($value) eq "ARRAY";
                        
                        # if there is a single null, the not in clause will be false
                        if ($value->{""}) {
                            @hr = ();
                        }
                        else {
                            # return everything NOT in the hash
                            my @thr;
                            for my $h (@hr) {
                                for my $k (sort keys %$h) {
                                    next unless length($k);                                
                                    unless ($value->{$k}) {
                                        push @thr, $h->{$k};
                                    }
                                }
                            }
                            @hr = grep { $_ } @thr;
                        }
                    } elsif($op =~ /^\!\=$/) {                        
                        my @thr;
                        foreach my $h (@hr) {
                            foreach my $k (sort keys %$h) {
                                if($k != $value->{value}) {
                                    push @thr, $h->{$k};
                                }
                            }
                        }
                        @hr = grep { $_ } @thr;
                    } elsif($op =~ /^\>$/i) {
                        my @thr;
                        foreach my $h (@hr) {
                            foreach my $k (keys %$h) {
                                if($k > $value->{value}) {
                                    push @thr, $h->{$k};
                                }
                            }
                        }
                        @hr = grep { $_ } @thr;
                    } elsif($op =~ /^\<$/i) {
                        my @thr;
                        foreach my $h (@hr) {
                            foreach my $k (keys %$h) {
                                if($k < $value->{value}) {
                                    push @thr, $h->{$k};
                                }
                            }
                        }
                        @hr = grep { $_ } @thr;
                    } elsif($op =~ /^\>=$/i) {
                        my @thr;
                        foreach my $h (@hr) {
                            foreach my $k (keys %$h) {
                                if($k >= $value->{value}) {
                                    push @thr, $h->{$k};
                                }
                            }
                        }
                        @hr = grep { $_ } @thr;
                    } elsif($op =~ /^\<=$/i) {
                        my @thr;
                        foreach my $h (@hr) {
                            foreach my $k (keys %$h) {
                                if($k <= $value->{value}) {
                                    push @thr, $h->{$k};
                                }
                            }
                        }
                        @hr = grep { $_ } @thr;
                    } elsif($op =~ /^ne$/i) {
                        my @thr;
                        foreach my $h (@hr) {
                            foreach my $k (sort keys %$h) {
                                if($k ne $value->{value}) {
                                    push @thr, $h->{$k};
                                }
                            }
                        }
                        @hr = grep { $_ } @thr;                        
                    } elsif($op =~ /^<>/) {
                        my @thr;
                        foreach my $h (@hr) {
                            foreach my $k (sort keys %$h) {
                                if(length($k) and length($value->{value}) and $k ne $value->{value}) {
                                    push @thr, $h->{$k};
                                }
                            }
                        }
                        @hr = grep { $_ } @thr;                        
                    } elsif($op eq "between") {
                        my @thr;
                        my ($min,$max) = @{ $value->{value} };
                        foreach my $h (@hr) {
                            foreach my $k (sort keys %$h) {
                                if(length($k) and $k >= $min and $k <= $max) {
                                    push @thr, $h->{$k};
                                }
                            }
                        }
                        @hr = grep { $_ } @thr;                                      
                    } else {
                        use Data::Dumper;
                        Carp::confess("Unknown operator in key-value pair used in index lookup for index " . Dumper($value));
                    }
                }
                else
                {
                    Carp::confess("No operator specified in hashref value!" . Dumper($value));
                }
            } 
        }            
        return (map { values(%$_) } @hr);
    }


# this is called by delete() and unload() to do cleanup

    sub delete_object
    {
        my $self = shift;
        if (my $subscription = delete $self->{_get_change_subscription})
        {
            # cancel this
        }
        return $self->SUPER::delete_object(@_);
    }

# private methods

    sub _build_data_tree
    {        
        my $self = $_[0];
        
        my @indexed_property_names = $self->indexed_property_names;        
        my $hr_base = $self->{data_tree};
        
        # _remove_object in bulk.
        %$hr_base = ();
        my $indexed_class_name = $self->indexed_class_name;
        
        if (my @bad_properties = 
            grep { not $indexed_class_name->can($_) }
            @indexed_property_names
        ) {
            Carp::confess(
                "Attempt to index $indexed_class_name by properties which "
                . "do not function:  @bad_properties"
            );
        }
        
        # _add_object in bulk.
        no warnings;
        my ($object,@values,$hr,$value);
        for my $object ($self->indexed_class_name->all_objects_loaded)
        {            
            @values = map { $object->$_ } @indexed_property_names;
            $hr = $hr_base;
            for $value (@values)
            {
                $hr->{$value} ||= {};
                $hr = $hr->{$value};
            }            
            $hr->{$object->id} = $object;
        }
        
    }
    
    sub _setup_change_subscription
    {
        
        my $self = shift;
        
        
        my $indexed_class_name = $self->indexed_class_name;        
        my @indexed_property_names = $self->indexed_property_names;
        
        if (1) {            
            # This is a new indexing strategy which pays at index creation time instead of use.
            
            my @properties_to_watch = (@indexed_property_names, qw/create delete load unload define/);
            #print "making index $self->{id}\n";
            for my $class ($indexed_class_name, @{ $UR::Object::_init_subclasses_loaded{$indexed_class_name} }) {        
                for my $property (@properties_to_watch) {
                    my $index_list = $UR::Object::Index::all_by_class_name_and_property_name{$class}{$property} ||= [];
                    #print " adding to $class\n";
                    push @$index_list, $self;
                }
            }
            
            return 1;
        }
        
        # This will be ignored for now.
        # If the signal_change/subscription system is improved, it may be better to go back?
        
        my %properties_to_watch = map { $_ => 1 } (@indexed_property_names, qw/create delete load unload define/);
        
        $self->{_get_change_subscription} = $indexed_class_name->create_subscription(            
            callback => 
                sub
                {            
                    my ($changed_object, $changed_property, $old_value, $new_value) = @_;
                    
                    #print "got change $changed_property for $indexed_class_name: $changed_object->{id}: @_\n";
                    
                    # ensure we don't track changes for subclasses
                    #return() unless ref($changed_object) eq $indexed_class_name;
                    
                    # ensure we only add/remove for selected method calls
                    return() unless $properties_to_watch{$_[1]};
                    
                    #print "changing @_\n";
                    
                    $self->_remove_object(
                        $changed_object, 
                        { $changed_property => $old_value }
                    ) unless $changed_property =~ /^(create|load|define)$/;
                    
                    $self->_add_object($changed_object) unless $changed_property =~ /^(delete|unload)$/;
                },
            note => "index monitor " . $self->id,
            priority => 0,
        );        
    }

    sub _get_change_subscription
    {        
        # accessor for the change subscription
        $_[0]->{_get_change_subscription} = $_[1] if (@_ > 1);
        return $_[0]->{_get_change_subscription};
    }

    sub _remove_object($$)
    {
        no warnings;
        
        my ($self, $object, $overrides) = @_;
        my @indexed_property_names = $self->indexed_property_names;
        my @values = 
            map 
            { 
                ($overrides && exists($overrides->{$_}))
                ? 
                $overrides->{$_} 
                : 
                $object->$_ 
            }
            @indexed_property_names;
            
        my $hr = $self->{data_tree};
        my $value;
        for $value (@values)
        {            
            $hr = $hr->{$value};
        }
        delete $hr->{$object->id};
    }

    sub _add_object($$)
    {
        # We get warnings when undef converts into an empty string.
        # For efficiency, we turn warnings off in this method.
        no warnings;
        
        my ($self, $object) = @_;
        my @indexed_property_names = $self->indexed_property_names;
        my @values = map { $object->$_ } @indexed_property_names;        
        my $hr = $self->{data_tree};
        my $value;
        for $value (@values)
        {            
            $hr->{$value} ||= {};
            $hr = $hr->{$value};
        }
        $hr->{$object->id} = $object;        
        
        # This is the exact formula used elsewhere.  TODO: refactor, base on class meta
        if ($UR::Context::light_cache and substr($self->indexed_class_name,0,5) ne 'App::') {
            Scalar::Util::weaken($hr->{$object->id});
        }
    }

1;


