
=head1 NAME

UR::BoolExpr::Template - an UR::BoolExpr minus specific values

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

package UR::BoolExpr::Template;

use warnings;
use strict;

use Scalar::Util qw(blessed);
use Data::Dumper;
use UR;

UR::Object::Type->define(
    class_name  => __PACKAGE__, 
    is_transactional => 0,
    composite_id_separator => '/',
    id_by => [
        subject_class_name              => { is => 'Text' },
        logic_type                      => { is => 'Text' },
        logic_detail                    => { is => 'CSV' },
        constant_value_id               => { is => 'Text' }
    ],
    has => [
        is_normalized                   => { is => 'Boolean' },
        is_id_only                      => { is => 'Boolean' },
        is_partial_id                   => { is => 'Boolean' },  # True if at least 1, but not all the ID props are mentioned
        is_normalized                   => { is => 'Boolean' },
        is_unique                       => { is => 'Boolean' },
        matches_all                     => { is => 'Boolean' },
        key_op_hash                     => { is => 'HASH' },
        num_values                      => { is => 'Integer' },
        recursion_desc                  => { is => 'ARRAY' },
        id_position                     => { is => 'Integer' },
        normalized_id                   => { is => 'Text' },        
        normalized_positions_arrayref   => { is => 'ARRAY' },        
        normalization_extender_arrayref => { is => 'ARRAY' },
        _property_meta_hash             => { is => 'HASH' },
        _property_names_arrayref        => { is => 'ARRAY' },
    ],
);

our $VERSION = '0.1';

# Borrow from the util package.
# This will go away with refactoring.

our $id_sep         = $UR::BoolExpr::Util::id_sep;
our $record_sep     = $UR::BoolExpr::Util::record_sep;
our $unit_sep       = $UR::BoolExpr::Util::unit_sep;
our $null_value     = $UR::BoolExpr::Util::null_value;
our $empty_string   = $UR::BoolExpr::Util::empty_string;
our $empty_list     = $UR::BoolExpr::Util::empty_list;
*values_to_value_id         = \&UR::BoolExpr::Util::values_to_value_id;
*value_id_to_values         = \&UR::BoolExpr::Util::value_id_to_values;
*values_to_value_id_frozen  = \&UR::BoolExpr::Util::values_to_value_id_frozen;
*value_id_to_values_frozen  = \&UR::BoolExpr::Util::value_id_to_values_frozen;


# Wrappers for regular properties

sub _property_names {
    return @{ $_[0]->{_property_names_arrayref} };
}

sub _constant_values {
    my $self = shift;
    if (@_) {
        $self->constant_value_id($self->values_to_value_id(@_));
    }
    my $constant_value_id = $self->constant_value_id;
    return unless $constant_value_id;
    return $self->value_id_to_values($constant_value_id);
}


# This is set lazily currently

sub is_unique {
    my $self = $_[0];
    if (defined $self->{is_unique}) {
        return $self->{is_unique}
    }

    # since this requires normalization, we don't set the value at construction time
    my $normalized_self;
    if ($self->is_normalized) {
        $normalized_self = $self;
    }
    else {
        $normalized_self = $self->get_normalized_template_equivalent($self);
    }

    my $op = $normalized_self->operator_for_property_name('id');
    if (defined($op) and ($op eq '' or $op eq '=')) {
        return $self->{is_unique} = 1;
    }
    else {
        $self->{is_unique} = 0;
        
        # if some combination of params can combine to
        # satisfy at least one unique constraint,
        # then we have uniqueness in the parameters.

        if (my @ps = $self->subject_class_name->get_class_object->unique_property_sets) {  
            my $property_meta_hash = $self->_property_meta_hash;      
            for my $property_set (@ps) 
            {
                my $property_set = (ref($property_set) ? $property_set : [$property_set]);
                my @properties_used_from_constraint =  
                    grep { defined($_) } 
                    (ref($property_set) ? @$property_meta_hash{@$property_set} : $property_meta_hash->{$property_set});
                    
                if (@properties_used_from_constraint == @$property_set) {
                    # filter imprecise operators
                    @properties_used_from_constraint = 
                        grep {  
                            $_->{operator} !~ /^(not |)like(-.|)$/i
                            and
                            $_->{operator} ne '[]'
                            and
                            $_->{operator} !~ /^(not |)in/i
                        }                                              
                        @properties_used_from_constraint;
                        
                    if (@properties_used_from_constraint == @$property_set) {
                        $self->{is_unique} = 1;
                        last;
                    }
                    else {
                        ## print "some properties use bad operators: @properties_used_from_constraint\n";
                    }
                }
                else {
                    ## print "too few properties in @properties_used_from_constraint\n";
                }
            }
        }

        return $self->{is_unique};
    }
}


# Derivative of the ID. 

sub rule_template_subclass_name {    
    return "UR::BoolExpr::Template::" . shift->logic_type;
}

sub get_normalized_template_equivalent {
    UR::BoolExpr::Template->get($_[0]->{normalized_id});
}

sub get_rule_for_values {
    my $self = shift;
    my $value_id = $self->values_to_value_id(@_);    
    my $rule_id = UR::BoolExpr->composite_id($self->id,$value_id);
    return UR::BoolExpr->get($rule_id);
}

sub get_normalized_rule_for_values {
    my $self = shift;
    my @unnormalized_values = @_;

    if ($self->is_normalized) {
        return $self->get_rule_for_values(@unnormalized_values);
    }

    my $normalized_rule_template = $self->get_normalized_template_equivalent;

    # The normalized rule set may have more values than were actually
    # passed-in.  These 'extenders' will add to the @values array
    # before re-ordering it.
    my $extenders = $self->normalization_extender_arrayref;
    if (@$extenders) {
        my $subject_class = $self->subject_class_name;
        for my $extender (@$extenders) {
            my ($input_positions_arrayref,$subref) = @$extender;
            my @more_values = @unnormalized_values[@$input_positions_arrayref];            
            if ($subref) {
                ## print "calling $subref on \n\t" . join("\n\t",@more_values) . "\n";
                @more_values = $subject_class->$subref(@more_values);
                ## print "got: \n\t" . join("\n\t",@more_values) . "\n";
            }
            push @unnormalized_values, @more_values;
        }
    }
    
    # Normalize the values.  Since the normalized template may have added properties, 
    # and a different order we may need to re-order and expand the values list.
    my $normalized_positions_arrayref = $self->normalized_positions_arrayref;
    my @normalized_values = @unnormalized_values[@$normalized_positions_arrayref];

    my $rule = $normalized_rule_template->get_rule_for_values(@normalized_values);
    return $rule;
}


sub value_position_for_property_name {
    if (exists $_[0]{_property_meta_hash}{$_[1]}) {
        return $_[0]{_property_meta_hash}{$_[1]}{value_position};
    } else {
        return undef;
    }
}

sub operator_for_property_name {
    if (exists $_[0]{_property_meta_hash}{$_[1]}) {
        return $_[0]{_property_meta_hash}{$_[1]}{operator};
    } else {
        return undef;
    }
}

sub add_filter {
    my $self = shift;
    my $property_name = shift;
    my $op = shift;    
    my $new_key = $property_name;
    $new_key .= ' ' . $op if defined $op;    
    my ($subject_class_name, $logic_type, $logic_detail) = split("/",$self->id);
    unless ($logic_type eq 'And') {
        die "Attempt to add a filter to a rule besides an 'And' rule!";
    }
    my @keys = split(',',$logic_detail);
    my $new_id = join('/',$subject_class_name,$logic_type,join(',',@keys,$new_key));
    return $self->class->get($new_id);
}

sub remove_filter {
    my $self = shift;
    my $filter = shift;
    my ($subject_class_name, $logic_type, $logic_detail) = split("/",$self->id);
    my @keys = grep { $_ !~ /^${filter}\b/ } split(',',$logic_detail);
    my $new_id = join('/',$subject_class_name,$logic_type,join(',',@keys));
    #print "$new_id\n";
    return $self->class->get($new_id);
}

sub sub_classify {
    my ($self,$subclass_name) = @_;
    my $new_id = $self->id;
    $new_id =~ s/^.*?\//$subclass_name\//;
    return $self->class->get($new_id);    
}


# flyweight constructor
# NOTE: this caches outside of the regulary system since these are stateless objects

sub get_by_subject_class_name_logic_type_and_logic_detail {
    my $class = shift;
    my $subject_class_name = shift;
    my $logic_type = shift;
    my $logic_detail = shift;
    my $constant_value_id = $class->values_to_value_id(); # intentionally an empty list of values
    return $class->get(join('/',$subject_class_name,$logic_type,$logic_detail,$constant_value_id));
}

sub get {
    my $class = shift;
    my $id = shift;    
    die "Non-id params not supported for " . __PACKAGE__ . " yet!" if @_;

    # get if possible
    my $self = $UR::Object::rule_templates{$id};
    return $self if $self;     

    my ($subject_class_name,$logic_type,$logic_detail,$constant_value_id,@extra) = split('/',$id);  
    if (@extra) {
        # account for a possible slash in the constant value id
        $constant_value_id = join('/',$constant_value_id,@extra);
    }

    my $sub_class_name = (
        $class eq __PACKAGE__ 
            ? __PACKAGE__ . "::" . $logic_type
            : $class    
    );

    unless ($logic_type) {
        Carp::confess($id);
    }

    my @extra_params;
    if ($logic_type eq "And") {
        # TODO: move into subclass
        my (@keys, $num_values);
            
        @keys = split(',',$logic_detail || '');
        $num_values = scalar(@keys);
    
        # See what properties are id-related for the class
        my $id_related = $UR::Object::id_related{$subject_class_name};
        my $id_pos = $UR::Object::id_pos{$subject_class_name};
        my $id_translations = $UR::Object::id_translations{$subject_class_name};    
        
        unless ($id_related) {
            $id_related = {};
            $id_translations = [];
            $id_pos = {};
            for my $iclass ($subject_class_name, $subject_class_name->inheritance) {
                last if $iclass eq "UR::Object";
                next unless $iclass->isa("UR::Object");
                my $iclass_meta = $iclass->get_class_object;
                my @id_props = $iclass_meta->id_property_names;
                next unless @id_props;
                next if @id_props == 1 and $id_props[0] eq "id";
                push @$id_translations, \@id_props;
                @$id_related{@id_props} = @id_props;
                @$id_pos{@id_props} = (0..$#id_props);
            }
            $UR::Object::id_related{$subject_class_name} = $id_related;
            $UR::Object::id_translations{$subject_class_name} = $id_translations;
            $UR::Object::id_pos{$subject_class_name} = $id_pos;
        }
        
        # Make a hash to quick-validate the params for duplication
        no warnings; 
        my %check_for_duplicate_rules;
        for (my $n=0; $n < @keys; $n++) {
            my ($property,$op) = ($keys[$n] =~ /^(\w+)\b(.*)$/);
            $check_for_duplicate_rules{$property}++;
        }

        my $id_position = undef;
        my $var_pos = 0;
        my $const_pos = 0;
        my $property_meta_hash = {};        
        my $property_names = [];
        for my $key (@keys) {
            if ($key =~ /^id\b/) {
                $id_position = $var_pos;
            }
            if (substr($key,0,1) eq '-') {
                $property_meta_hash->{$key} = {
                    name => $key,
                    value_position => $const_pos
                };
                $const_pos++;
            }
            else {
                my ($name, $op) = ($key =~ /^(.+?)\b\s*(.*)$/);
                $property_meta_hash->{$name} = {
                    name => $name,
                    operator => $op,
                    value_position => $var_pos
                };        
                $var_pos++;
                push @$property_names, $name;
            }
    
        }

    
        # Add value extenders for any cases of id-related properties,
        # or aliases.
        my $extenders = [];    
        my $rule_template_id;    
        
        # Note whether there are properties not involved in the ID
        my $id_only = 1;
        my $partial_id = 0;
        
        my $key_op_hash = {};
        if (@$id_translations and @{$id_translations->[0]} == 1) {
            # single-property ID
            ## use Data::Dumper;
            ## print "single property id\n". Dumper($id_translations);
            my ($key_pos,$key,$property,$op,$x);
            my $original_key_count = @keys;
    
            # Presume we are only getting id properties until another is found.
            # If a multi-property is partially specified, we'll zero this out too.
            
            for ($key_pos = 0; $key_pos < $original_key_count; $key_pos++) {
                $key = $keys[$key_pos];
    
                ($property,$op) = ($key =~ /^(\w+)\b(.*)$/);  # /^(\w+)\b\S*(.*)$/
                $op ||= "";
                $op =~ s/\s+//;
                $key_op_hash->{$property} ||= {};
                $key_op_hash->{$property}{$op}++;
                
                ## print "> $key_pos- $key: $property/$op\n";
                if ($property eq "id" or $id_related->{$property}) {
                    # Put an id key into the key list.
                    for my $alias (["id"], @$id_translations) {
                        next if $alias->[0] eq $property;
                        next if $check_for_duplicate_rules{$alias->[0]};
                        $op ||= "";
                        push @keys, $alias->[0] . ($op ? " $op" : ""); 
                        push @$extenders, [ [$key_pos], undef ];
                        $key_op_hash->{$alias->[0]} ||= {};
                        $key_op_hash->{$alias->[0]}{$op}++;
                        ## print ">> extend for @$alias with op $op.\n";
                    }
                    unless ($op =~ m/^(=|eq|in|\[\]|)$/) {
                        $id_only = 0;
                    }
                }    
                else {
                    $id_only = 0;
                    ## print "non id single property $property on $subject_class\n";
                }
            }            
        }
        else {
            # multi-property ID
            ## print "multi property id\n". Dumper($id_translations);
            my ($key_pos,$key,$property,$op);
            my $original_key_count = @keys;
            my %id_parts;
            for ($key_pos = 0; $key_pos < $original_key_count; $key_pos++) {
                $key = $keys[$key_pos];                
                ($property,$op) = ($key =~ /^(\w+)\b(.*)$/);  # /^(\w+)\b\S*(.*)$/
                $op ||= "";
                $op =~ s/\s+//;                
                $key_op_hash->{$property} ||= {};
                $key_op_hash->{$property}{$op}++;
                
                ## print "> $key_pos- $key: $property/$op\n";
                if ($property eq "id") {
                    $key_op_hash->{id} ||= {};
                    $key_op_hash->{id}{$op}++;                    
                    # Put an id-breakdown key into the key list.
                    for my $alias (@$id_translations) {
                        my @new_keys = map {  $_ . ($op ? " $op" : "") } @$alias; 
                        if (grep { $check_for_duplicate_rules{$_} } @new_keys) {
                            #print "up @new_keys with @$alias\n";
                        }
                        else {
                            push @keys, @new_keys; 
                            push @$extenders, [ [$key_pos], "decomposed_id" ];
                            for (@$alias) {
                                $key_op_hash->{$_} ||= {};
                                $key_op_hash->{$_}{$op}++;
                            }
                            # print ">> extend for @$alias with op $op.\n";
                        }
                    }
                }    
                elsif ($id_related->{$property}) {
                    #if ($op eq "" or $op eq "eq" or $op eq "=" or $op eq '[]') {
                    if ($op eq "" or $op eq "eq" or $op eq "=") {
                        $id_parts{$id_pos->{$property}} = $key_pos;                        
                    }
                    else {
                        # We're doing some sort of gray-area comparison on an ID                        
                        # field, and though we could possibly resolve an ID
                        # from things like an [] op, it's more than we've done
                        # before.
                        $id_only = 0;
                    }
                }
                else {
                    ## print "non id multi property $property on class $subject_class\n";
                    $id_only = 0;
                }
            }            
            
            if (my $parts = (scalar(keys(%id_parts)))) {
                # some parts are id-related                
                if ($parts ==  @{$id_translations->[0]}) { 
                    # all parts are of the id are there 
                    if (@$id_translations) {
                        if (grep { $_ eq 'id' } @keys) {
                            #print "found id already\n";
                        }
                        else {
                            #print "no id\n";
                            # we have translations of that ID into underlying properties
                            #print "ADDING ID for " . join(",",keys %id_parts) . "\n";
                            my @id_pos = sort { $a <=> $b } keys %id_parts;
                            push @$extenders, [ [@id_parts{@id_pos}], "composite_id" ];
                            $key_op_hash->{id} ||= {};
                            $key_op_hash->{id}{$op}++;                        
                            push @keys, "id"; 
                        }   
                    }
                }
                else {
                    # not all parts of the id are there
                    ## print "partial id property $property on class $subject_class\n";
                    $id_only = 0;
                    $partial_id = 1;
                }
            }
        }
        
        # Determine the positions of each key in the parameter list.                        
        my %key_positions;
        my $pos = 0;
        for my $key (@keys) {
            $key_positions{$key} ||= [];
            push @{ $key_positions{$key} }, $pos++;    
        }
    
        # Sort the keys, and make an arrayref which will 
        # re-order the values to match.
        my @keys_sorted = sort @keys;
        my $matches_all = scalar(@keys_sorted) == 0 ? 1 : 0;
        my $normalized_positions_arrayref = [];
        my $constant_value_normalized_positions = [];
        my $recursion_desc = undef;
        for my $key (@keys_sorted) {
            my $pos_list = $key_positions{$key};
            my $pos = shift @$pos_list;
            if (substr($key,0,1) eq '-') {
                push @$constant_value_normalized_positions, $pos;
                if ($key eq '-recurse') {
                    my @values = UR::BoolExpr::Template->value_id_to_values($constant_value_id);
                    $DB::single = 1;
                    $recursion_desc = $values[0];
                }
            }
            else {
                push @$normalized_positions_arrayref, $pos;
            }
        }

        $id_only = 0 if ($matches_all);
    
        if (@$constant_value_normalized_positions > 1) {
            Carp::confess("Not Implemented: multiple '-' options.  Fix me!");
        }
        
        # Determine the rule template's ID.
        # The normalizer will store this.  Below, we'll
        # find or create the template for this ID.
        my $normalized_id = UR::BoolExpr::Template->composite_id($subject_class_name, "And", join(",",@keys_sorted), $constant_value_id);
        
        @extra_params = (
            id_position                     => $id_position,        
            is_id_only                      => $id_only,
            is_partial_id                   => $partial_id,
            is_unique                       => undef, # assigned on first use
            matches_all                     => $matches_all,
    
            key_op_hash                     => $key_op_hash,
            num_values                      => $num_values,
            _property_names_arrayref        => $property_names,
            _property_meta_hash             => $property_meta_hash,
    
            recursion_desc                  => $recursion_desc,
    
            is_normalized                   => ($id eq $normalized_id ? 1 : 0),
            normalized_id                   => $normalized_id,        
            normalized_positions_arrayref   => $normalized_positions_arrayref,
            normalization_extender_arrayref => $extenders,
        );
    } # done generating smecial data for the "And" rule to normalize itself
    else {
        @extra_params = (normalized_id => $id);
    }
    
    $self = bless {
        id                              => $id,
        subject_class_name              => $subject_class_name,
        logic_type                      => $logic_type,
        logic_detail                    => $logic_detail,
        constant_value_id               => $constant_value_id,
        @extra_params
    }, $sub_class_name;
    $UR::Object::rule_templates{$id} = $self;  
    #print Data::Dumper::Dumper($self);
    return $self;
}


# This is the basis for the hash used by the existing UR::Object system for each rule.
# this is created upon first request and cached in the object

sub legacy_params_hash {
    my $self = shift;
    my $legacy_params_hash = $self->{legacy_params_hash};
    return $legacy_params_hash if $legacy_params_hash;
    
    $legacy_params_hash = {};    
    
    my $rule_template_id = $self->id;
    my $key_op_hash = $self->key_op_hash;
    my $id_only = $self->is_id_only;    
        
    my $subject_class_name  = $self->subject_class_name;
    my $logic_type          = $self->logic_type;    
    my $logic_detail        = $self->logic_detail;    
    my @keys_sorted         = $self->_underlying_keys;
    
    my $subject_class_meta  = $subject_class_name->get_class_object;
    
    if (
        (@keys_sorted and not $logic_detail)
        or
        ($logic_detail and not @keys_sorted)        
    ) {
        Carp::confess();
    }
    
    if (!$logic_detail) {
        %$legacy_params_hash = (_unique => 0, _none => 1);            
    }
    else {        
        # _id_only
        if ($id_only) {
            $legacy_params_hash->{_id_only} = 1;
        }
        else {
            $legacy_params_hash->{_id_only} = 0;
            $legacy_params_hash->{_param_key} = undef;
        }
        
        # _unique
        if (my $id_op = $key_op_hash->{id}) {
            if ($id_op->{""} or $id_op->{"="}) {
                $legacy_params_hash->{_unique} = 1;
                unless ($self->is_unique) {
                    warn "is_unique false unexpectedly for $self->{id}"
                }
            }
        }

                

        unless ($legacy_params_hash->{_unique}) {         
            if (defined $legacy_params_hash->{id} and not ref $legacy_params_hash->{id})
            {
                # if we have the id, then we have uniqueness
                $legacy_params_hash->{_unique} = 1;
            }
            else
            {
                # default to non-unique
                $legacy_params_hash->{_unique} = 0;   
               
                # if some combination of params can combine to
                # satisfy at least one unique constraint,
                # then we have uniqueness in the parameters.
                
                my @ps = $subject_class_meta->unique_property_sets;
                for my $property_set (@ps) 
                {                            
                    my $property_set = (ref($property_set) ? $property_set : [$property_set]);
                    my @properties_used_from_constraint =  
                        grep { defined($_) } 
                        (ref($property_set) ? @$key_op_hash{@$property_set} : $key_op_hash->{$property_set});
                        
                    if (@properties_used_from_constraint == @$property_set) {
                        # filter imprecise operators
                        @properties_used_from_constraint = 
                            grep {                                                
				                not (
                                    grep { /^(not |)like(-.|)$/i or /^\[\]/}
                                    keys %$_
                                )
                            }
                            @properties_used_from_constraint;
                            
                        if (@properties_used_from_constraint == @$property_set) {
                            $legacy_params_hash->{_unique} = 1;
                            last;
                        }
                        else {
                            ## print "some properties use bad operators: @properties_used_from_constraint\n";
                        }
                    }
                    else {
                        ## print "too few properties in @properties_used_from_constraint\n";
                    }
                }
            }
            
            # _param_key gets re-set as long as this has a true value
            $legacy_params_hash->{_param_key} = undef unless $id_only;
        }
    }

    if ($self->is_unique and not $legacy_params_hash->{_unique}) {
        warn "is_unique IS set but legacy params hash is NO for $self->{id}";
        $DB::single = 1;
        $self->is_unique; 
    }
    if (!$self->is_unique and $legacy_params_hash->{_unique}) {        
        warn "is_unique NOT set but legacy params hash IS for $self->{id}";
        $DB::single = 1;
        $self->is_unique; 
    }       

    $self->{legacy_params_hash} = $legacy_params_hash;
    return $legacy_params_hash;
}

1;

