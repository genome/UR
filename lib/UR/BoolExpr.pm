package UR::BoolExpr;
use warnings;
use strict;

use Scalar::Util qw(blessed);
require UR;

use Carp;
our @CARP_NOT = ('UR::Context');

our $VERSION = "0.31"; # UR $VERSION;;

# readable stringification
use overload ('""' => '__display_name__');
use overload ('==' => sub { $_[0] . ''  eq $_[1] . '' } );
use overload ('eq' => sub { $_[0] . ''  eq $_[1] . '' } );

UR::Object::Type->define(
    class_name => 'UR::BoolExpr',
    composite_id_separator => $UR::BoolExpr::Util::id_sep,
    id_by => [
        template_id         => { type => 'Blob' },
        value_id            => { type => 'Blob' },
    ],
    has => [
        template            => { is => 'UR::BoolExpr::Template', id_by => 'template_id' },
        subject_class_name  => { via => 'template' },
        logic_type          => { via => 'template' },
        logic_detail        => { via => 'template' },
        
        num_values          => { via => 'template' },
        is_normalized       => { via => 'template' },
        is_id_only          => { via => 'template' },
        has_meta_options    => { via => 'template' },
    ],
    is_transactional => 0,
);


# for performance
sub UR::BoolExpr::Type::resolve_composite_id_from_ordered_values {
    shift;
    return join($UR::BoolExpr::Util::id_sep,@_);
}

# only respect the first delimiter instead of splitting
sub UR::BoolExpr::Type::resolve_ordered_values_from_composite_id {
     my ($self,$id) = @_;
     my $pos = index($id,$UR::BoolExpr::Util::id_sep);
     return (substr($id,0,$pos), substr($id,$pos+1));
}

sub template {
    my $self = $_[0];
    return $self->{template} ||= $self->__template;
}

sub flatten {
    my $self = shift;
    return $self->{flatten} if exists $self->{flatten};
    my $flat = $self->template->_flatten_bx($self);
    $self->{flatten} = $flat;
    Scalar::Util::weaken($self->{flatten}) if $self == $flat;
    return $flat;
}

sub reframe {
    my $self = shift;
    my $in_terms_of = shift;
    return $self->{reframe}{$in_terms_of} if $self->{reframe}{$in_terms_of};
    my $reframe = $self->template->_reframe_bx($self, $in_terms_of);
    $self->{reframe}{$in_terms_of} = $reframe;
    Scalar::Util::weaken($self->{reframe}{$in_terms_of}) if $self == $reframe;
    return $reframe;
}


# override the UR/system display name
# this is used in stringification overload
sub __display_name__ {
    my $self = shift;
    my %b = $self->_params_list;
    my $s = Data::Dumper->new([\%b])->Terse(1)->Indent(0)->Useqq(1)->Dump;
    $s =~ s/\n/ /gs;
    $s =~ s/^\s*{//; 
    $s =~ s/\}\s*$//;
    $s =~ s/\"(\w+)\" \=\> / $1 => /g;
    return __PACKAGE__ . '=(' . $self->subject_class_name . ':' . $s . ')';
}

# The primary function: evaluate a subject object as matching the rule or not.
sub evaluate {
    my $self = shift;
    my $subject = shift;
    my $template = $self->template;
    my @values = $self->values;
    return $template->evaluate_subject_and_values($subject,@values);
}

# Behind the id properties:
sub template_and_values {
    my $self = shift;
    my ($template_id, $value_id) = UR::BoolExpr::Type->resolve_ordered_values_from_composite_id($self->id);
    return (UR::BoolExpr::Template->get($template_id), UR::BoolExpr::Util->value_id_to_values($value_id));
}

# Returns true if the rule represents a subset of the things the other
# rule would match.  It returns undef if the answer is not known, such as
# when one of the values is a list and we didn't go to the trouble of 
# searching the list for a matching value
sub is_subset_of {
    my($self, $other_rule) = @_;

    return 0 unless (ref($other_rule) and $self->isa(ref $other_rule));

    my $my_template = $self->template;
    my $other_template = $other_rule->template;

    unless ($my_template->isa("UR::BoolExpr::Template::And")
            and $other_template->isa("UR::BoolExpr::Template::And")) {
        Carp::confess("This method currently works only on ::And expressions.  Update to handle ::Or, ::PropertyComparison, and templates of mismatched class!");
    }
    return unless ($my_template->is_subset_of($other_template));

    my $values_match = 1;
    foreach my $prop ( $other_template->_property_names ) {
        my $my_operator = $my_template->operator_for($prop) || '=';
        my $other_operator = $other_template->operator_for($prop) || '=';

        my $my_value = $self->value_for($prop);
        my $other_value = $other_rule->value_for($prop);

        # If either is a list of values, return undef
        return undef if (ref($my_value) || ref($other_value));

        no warnings 'uninitialized';
        $values_match = undef if ($my_value ne $other_value);
    }

    return $values_match;
}

sub values {
    my $self = shift;
    if ($self->{values}) {
        return @{ $self->{values}}
    }
    my $value_id = $self->value_id;    
    return unless defined($value_id) and length($value_id);
    my @values;
    if (my $hard_refs = $self->{hard_refs}) {
        @values = UR::BoolExpr::Util->value_id_to_values($value_id);
        for my $n (keys %$hard_refs) {
            $values[$n] = $hard_refs->{$n};
        }
    }
    else {
        @values = UR::BoolExpr::Util->value_id_to_values($value_id);
    }
    $self->{values} = \@values;
    return @values;
}

sub value_for_id {
    my $self = shift;
    my $t = $self->template;
    my $position = $t->id_position;
    return unless defined $position;
    return $self->value_for_position($position);
}

sub specifies_value_for {
    my $self = shift;
    my $rule_template = $self->template;
    return $rule_template->specifies_value_for(@_);
}

sub value_for {
    my $self = shift;
    my $property_name = shift;
    
    # TODO: refactor to be more efficient
    my $h = $self->legacy_params_hash;
    my $v;
    if (exists $h->{$property_name}) {
        $v = $h->{$property_name};
    } else {
        # No value found under that name... try decomposing the id 
        return if $property_name eq 'id';
        my $id_value = $self->value_for('id');
        my $class_meta = $self->subject_class_name->__meta__();
        my @id_property_values = $class_meta->get_composite_id_decomposer->($id_value);
        
        my @id_property_names = $class_meta->id_property_names;
        for (my $i = 0; $i < @id_property_names; $i++) {
            if ($id_property_names[$i] eq $property_name) {
                $v = $id_property_values[$i];
                last;
            }
        }
    }
    return $v unless ref($v);
    return $v->{value} if ref($v) eq "HASH";
    return $v;
}

sub value_for_position {
    my ($self, $pos) = @_;
    return ($self->values)[$pos];    
}

sub operator_for {
    my $self = shift;
    my $t = $self->template;
    return $t->operator_for(@_);
}

sub underlying_rules { 
    my $self = shift;    
    my @values = $self->values;    
    return $self->template->get_underlying_rules_for_values(@values);
}

# De-compose the rule back into its original form.
sub params_list {
    # This is the reverse of the bulk of resolve.
    # It returns the params in list form, directly coercable into a hash if necessary.
    # $r = UR::BoolExpr->resolve($c1,@p1);
    # ($c2, @p2) = ($r->subject_class_name, $r->params_list);
    my $self = shift;
    my $template = $self->template;
    my @values_sorted = $self->values;
    return $template->params_list_for_values(@values_sorted);
}

# TODO: replace these with the logical set operations
# FIXME: the name is confusing b/c it doesn't mutate the object, it returns a different object
sub add_filter {
    my $self = shift;
    return __PACKAGE__->resolve($self->subject_class_name, $self->params_list, @_);
}

# TODO: replace these with the logical set operations
# FIXME: the name is confusing b/c it doesn't mutate the object, it returns a different object
sub remove_filter {
    my $self = shift;
    my $property_name = shift;
    my @params_list = $self->params_list;
    my @new_params_list;
    for (my $n=0; $n<=$#params_list; $n+=2) {
        my $key = $params_list[$n];
        if ($key =~ /^$property_name\b/) {
            next;
        }
        my $value = $params_list[$n+1];
        push @new_params_list, $key, $value;
    }
    return __PACKAGE__->resolve($self->subject_class_name, @new_params_list);
}

# as above, doesn't mutate, just returns a different bx
sub sub_classify {
    my ($self,$subclass_name) = @_;
    my ($t,@v) = $self->template_and_values();
    return $t->sub_classify($subclass_name)->get_rule_for_values(@v);
}

# flyweight constructor
# like regular UR::Value objects, but kept separate from the cache but kept
# out of the regular transaction cache so they alwasy vaporize when derefed
sub get {
    my $rule_id = pop;
    unless (exists $UR::Object::rules->{$rule_id}) {
        my $pos = index($rule_id,$UR::BoolExpr::Util::id_sep);
        my ($template_id,$value_id) = (substr($rule_id,0,$pos), substr($rule_id,$pos+1));
        my $rule = { id => $rule_id, template_id => $template_id, value_id => $value_id };    
        bless ($rule, "UR::BoolExpr");
        $UR::Object::rules->{$rule_id} = $rule;
        Scalar::Util::weaken($UR::Object::rules->{$rule_id});
        return $rule;
    }
    return $UR::Object::rules->{$rule_id};
}

# because these are weakened
sub DESTROY {
    delete $UR::Object::rules->{$_[0]->{id}};
}

sub resolve_normalized {
    my $class = shift;
    my ($unnormalized_rule, @extra) = $class->resolve(@_);
    my $normalized_rule = $unnormalized_rule->normalize();
    return if !defined(wantarray);
    return ($normalized_rule,@extra) if wantarray;
    if (@extra) {
        no warnings;
        my $rule_class = $normalized_rule->subject_class_name;
        Carp::confess("Extra params for class $rule_class found: @extra\n");
    }
    return $normalized_rule;
}

sub resolve_for_template_id_and_values {
    my ($class,$template_id, @values)  = @_;
    my $value_id = UR::BoolExpr::Util->values_to_value_id(@values);
    my $rule_id = $class->__meta__->resolve_composite_id_from_ordered_values($template_id,$value_id);
    $class->get($rule_id);
}

my $resolve_depth;
sub resolve {
    $resolve_depth++;
    Carp::confess("Deep recursion in UR::BoolExpr::resolve()!") if $resolve_depth > 10;

    # handle the case in which we've already processed the params into a boolexpr
    if ( @_ == 3 and ref($_[2]) and ref($_[2])->isa("UR::BoolExpr") ) {
        $resolve_depth--;
        return $_[2];
    }

    my $class = shift;
    my $subject_class = shift;
    Carp::confess("@_") if not $subject_class;
    # support for legacy passing of hashref instead of object or list
    # TODO: eliminate the need for this
    my @in_params;
    if (ref($_[0]) eq "HASH") {
	   @in_params = %{$_[0]};
    } 
    else {
	   @in_params = @_;
    }
    
    if (defined($in_params[0]) and $in_params[0] eq '-or') {
        shift @in_params;
        my @sub_queries = @{ shift @in_params };
        my $bx = UR::BoolExpr::Template::Or->_compose(
            $subject_class,
            @sub_queries,
        );
        return $bx;
    }

    if (@in_params == 1) {
        unshift @in_params, "id";
    }
    elsif (@in_params % 2 == 1) {
        Carp::carp("Odd number of params while creating $class: (",join(',',@in_params),")");
    }

    # split the params into keys and values
    # where an operator is on the right-side, it is moved into the key
    my $count = @in_params;
    my (@keys,@values,@constant_values,$key,$value,$property_name,$operator,@hard_refs);
    for(my $n = 0; $n < $count;) {
        $key = $in_params[$n++];
        $value = $in_params[$n++];

        if (substr($key,0,1) eq '-') {
            # these are keys whose values live in the rule template
            push @keys, $key;
            push @constant_values, $value;
            next;
        }

        if ($key eq '_id_only' or $key eq '_param_key' or $key eq '_unique' or $key eq '__get_serial' or $key eq '_change_count') {
            # skip the pair: legacy cruft
            next;
        } 
        
        my $pos = index($key,' ');
        if ($pos != -1) {
            # the key is "propname op"
            $property_name = substr($key,0,$pos);
            $operator = substr($key,$pos+1);
            if (substr($operator,0,1) eq ' ') {
               $operator =~ s/^\s+//; 
            }
        }
        else {
            # the key is "propname"
            $property_name = $key;
            $operator = '';
        }
        
        if (my $ref = ref($value)) {
            if ( (not $operator) and ($ref eq "HASH")) {
                if (
                    exists $value->{operator}
                    and exists $value->{value}
                ) {
                    # the key => { operator => $o, value => $v } syntax
                    # cannot be used with a value type of HASH
                    $operator = lc($value->{operator});
                    if (exists $value->{escape}) {
                        $operator .= "-" . $value->{escape}
                    }
                    $key .= " " . $operator;                    
                    $value = $value->{value};
                    $ref = ref($value);
                }
                else {
                    # the HASH is a value for the specified param 
                    push @hard_refs, scalar(@values), $value;
                }
            }
            
            if ($ref eq "ARRAY") {
                if (not $operator) {
                    # key => [] is the same as "key in" => []
                    $operator = 'in';
                    $key .= ' in';
                }
                elsif ($operator eq 'not') {
                    # "key not" => [] is the same as "key not in" 
                    $operator .= ' in';
                    $key .= ' in';
                }

                foreach my $val (@$value) {
                    if (ref($val)) {
                        # when there are any refs in the arrayref
                        # we must keep the arrayerf contents
                        # to reconstruct effectively
                        push @hard_refs, scalar(@values), $value;
                        last;
                    }
                }

            } # done handling ARRAY value 
        
        } # done handling ref values

        push @keys, $key;
        push @values, $value;
    }
    
    # the above uses no class metadata
    
    # this next section uses class metadata
    # it should be moved into the normalization layer

    my $subject_class_meta = $subject_class->__meta__;
    unless ($subject_class_meta) {
        Carp::croak("No class metadata for $subject_class?!");
    }

    my $subject_class_props =
        $subject_class_meta->{'cache'}{'UR::BoolExpr::resolve'} ||=
        { map {$_, 1}  ( $subject_class_meta->all_property_type_names) };
    
    my ($op,@extra);
    
    my $kn = 0;
    my $vn = 0;
    my $cn = 0;

    my @xadd_keys;
    my @xadd_values;
    my @xremove_keys;
    my @xremove_values;
    my @extra_key_pos;
    my @extra_value_pos;
    my @swap_key_pos;
    my @swap_key_value;
    my $complex_values = 0;
    
    for my $value (@values) {
        $key = $keys[$kn++];
        if (substr($key,0,1) eq '-') {
            $cn++;
            redo;
        }
        else {
            $vn++;
        }
        
        my $pos = index($key,' ');
        if ($pos != -1) {
            # "propname op" 
            $property_name = substr($key,0,$pos);
            $operator = substr($key,$pos+1);
            if (substr($operator,0,1) eq ' ') {
               $operator =~ s/^\s+//; 
            }
        }
        else {
            # "propname"
            $property_name = $key;
            $operator = '';
        }
        
        # account for the case where this parameter does
        # not match an actual property 
        if (!exists $subject_class_props->{$property_name} and index($property_name,'.') == -1) {
            if (substr($property_name,0,1) eq '_') {
                warn "ignoring $property_name in $subject_class bx construction!"
            }
            else {
                push @extra_key_pos, $kn-1;
                push @extra_value_pos, $vn-1;
                next;                
            }
        }
        
        my $ref = ref($value);
        if($ref) {
            $complex_values = 1;
            if ($ref eq "ARRAY" and $operator ne 'between' and $operator ne 'not between') {
                my $data_type;
                my $is_many;
                if ($UR::initialized) {
                    my $property_meta = $subject_class_meta->property_meta_for_name($property_name);
                    unless (defined $property_meta) {
                        Carp::croak("No property metadata for $subject_class property '$property_name' for rule parameters ($key => $value)\n" . Data::Dumper::Dumper({ @_ }));
                    }
                    $data_type = $property_meta->data_type;
                    $is_many = $property_meta->is_many;                    
                }
                else {
                    $data_type = $subject_class_meta->{has}{$property_name}{data_type};
                    $is_many = $subject_class_meta->{has}{$property_name}{is_many};        
                }
                $data_type ||= '';
                
                if ($data_type eq 'ARRAY') {
                    # ensure we re-constitute the original array not a copy
                    push @hard_refs, $vn-1, $value;
                    push @swap_key_pos, $vn-1;
                    push @swap_key_value, $property_name;
                }
                elsif (not $is_many) {
                    no warnings;
                    
                    # sort and replace
                    $value = [ 
                        sort { $a <=> $b or $a cmp $b } 
                        @$value
                    ];         
                    
                    if ($operator ne 'between' and $operator ne 'not between') {
                        my $last = $value;
                        for (my $i = 0; $i < @$value;) {
                            if ($last eq $value->[$i]) {
                                splice(@$value, $i, 1);
                            }
                            else {
                                $last = $value->[$i++];
                             }
                         }
                     }
                    # push @swap_key_pos, $vn-1;
                    # push @swap_key_value, $property_name;
                }
                else {
                    # disable: break 47, enable: break 62
                    #push @swap_key_pos, $vn-1;
                    #push @swap_key_value, $property_name;
                }
            }
            elsif (blessed($value)) {
                my $property_meta = $subject_class_meta->property_meta_for_name($property_name);
                unless ($property_meta) {
                    for my $class_name ($subject_class_meta->ancestry_class_names) {
                        my $class_object = $class_name->__meta__;
                        $property_meta = $subject_class_meta->property_meta_for_name($property_name);
                        last if $property_meta;
                    }
                    unless ($property_meta) {
                        Carp::croak("No property metadata for $subject_class property '$property_name'");
                    }
                }

                if ($property_meta->is_delegated) {
                    my $property_meta = $subject_class_meta->property_meta_for_name($property_name);
                    unless ($property_meta) {
                        Carp::croak("No property metadata for $subject_class property '$property_name'");
                    }
                    my @joins = $property_meta->get_property_name_pairs_for_join();
                    for my $join (@joins) {
                        # does this really work for >1 joins?
                        my ($my_method, $their_method) = @$join;
                        push @xadd_keys, $my_method;
                        push @xadd_values, $value->$their_method;
                    }
                    # TODO: this may need to be moved into the above get_property_name_pairs_for_join(),
                    # but the exact syntax for expressing that this is part of the join is unclear.
                    if (my $id_class_by = $property_meta->id_class_by) {
                        push @xadd_keys, $id_class_by;
                        push @xadd_values, ref($value);
                        #print ":: @xkeys\n::@xvalues\n\n";
                    }
                    push @xremove_keys, $kn-1;
                    push @xremove_values, $vn-1;
                }
                elsif ($value->isa($property_meta->data_type)) {
                    push @hard_refs, $vn-1, $value;
                }
                elsif ($value->can($property_name)) {
                    # TODO: stop suporting foo_id => $foo, since you can do foo=>$foo, and foo_id=>$foo->id  
                    $DB::single = 1;
                    # Carp::cluck("using $property_name => \$obj to get $property_name => \$obj->$property_name is deprecated...");
                    $value = $value->$property_name;
                }
                else {
                    Carp::croak("Incorrect data type in rule " . ref($value) . " for $subject_class property '$property_name' with op $operator!");    
                }
                # end of handling a value which is an arrayref
            }
            elsif ($ref ne 'HASH') {
                # other reference, code, etc.
                push @hard_refs, $vn-1, $value;
            }
        }
    }
    push @keys, @xadd_keys;
    push @values, @xadd_values;

    if (@swap_key_pos) {
        @keys[@swap_key_pos] = @swap_key_value;
    }

    if (@extra_key_pos) {
        push @xremove_keys, @extra_key_pos;
        push @xremove_values, @extra_value_pos;
        for (my $n = 0; $n < @extra_key_pos; $n++) {
            push @extra, $keys[$extra_key_pos[$n]], $values[$extra_value_pos[$n]];
        }
    }
    
    if (@xremove_keys) {
        my @new;
        my $next_pos_to_remove = $xremove_keys[0];
        for (my $n = 0; $n < @keys; $n++) {
            if (defined $next_pos_to_remove and $n == $next_pos_to_remove) {
                shift @xremove_keys;
                $next_pos_to_remove = $xremove_keys[0];
                next;
            }
            push @new, $keys[$n];            
        }
        @keys = @new;        
    }

    if (@xremove_values) {
        if (@hard_refs) {
            # shift the numbers down to account for positional removals
            for (my $n = 0; $n < @hard_refs; $n+=2) {
                my $ref_pos = $hard_refs[$n];
                for my $rem_pos (@xremove_values) {
                    if ($rem_pos < $ref_pos) {
                        $hard_refs[$n] -= 1;
                        #print "$n from $ref_pos to $hard_refs[$n]\n";
                        $ref_pos = $hard_refs[$n];
                    }
                    elsif ($rem_pos == $ref_pos) {
                        $hard_refs[$n] = '';
                        $hard_refs[$n+1] = undef;
                    }
                }
            }
        }
        
        
        my @new;
        my $next_pos_to_remove = $xremove_values[0];
        for (my $n = 0; $n < @values; $n++) {
            if (defined $next_pos_to_remove and $n == $xremove_values[0]) {
                shift @xremove_values;
                $next_pos_to_remove = $xremove_values[0];
                next;
            }
            push @new, $values[$n];            
        }
        @values = @new;        
    }    

    my $template;
    if (@constant_values) {
        $template = UR::BoolExpr::Template::And->_fast_construct(
            $subject_class,
            \@keys,
            \@constant_values,
        );
    }
    else {
        $template = $subject_class_meta->{cache}{"UR::BoolExpr::resolve"}{"template for class and keys without constant values"}{"$subject_class @keys"} 
            ||= UR::BoolExpr::Template::And->_fast_construct(
                $subject_class,
                \@keys,
                \@constant_values,
            );
    }

    my $value_id = ($complex_values ? UR::BoolExpr::Util->values_to_value_id(@values) : UR::BoolExpr::Util->values_to_value_id_simple(@values) );
    
    my $rule_id = join($UR::BoolExpr::Util::id_sep,$template->{id},$value_id);

    my $rule = __PACKAGE__->get($rule_id); # flyweight constructor

    $rule->{template} = $template;
    $rule->{values} = \@values;
    
    $vn = 0;
    $cn = 0;
    my @list;
    for my $key (@keys) {
        push @list, $key;
        if (substr($key,0,1) eq '-') {
            push @list, $constant_values[$cn++];
        }
        else {
            push @list, $values[$vn++];
        }
    }
    $rule->{_params_list} = \@list;

    if (@hard_refs) {
        $rule->{hard_refs} = { @hard_refs };
        delete $rule->{hard_refs}{''};
    }

    $resolve_depth--;
    if (wantarray) {
        return ($rule, @extra);
    } 
    elsif (@extra && defined wantarray) {
        Carp::confess("Unknown parameters in rule for $subject_class: " . join(",", map { defined($_) ? "'$_'" : "(undef)" } @extra));
    }
    else {
        return $rule;
    }
}

sub _params_list {
    my $list = $_[0]->{_params_list} ||= do {
        my $self = $_[0];
        my $template = $self->template;        
        $self->values unless $self->{values};
        my @list;
        # are method calls really too expensive here?
        my $template_class = ref($template);
        if ($template_class eq 'UR::BoolExpr::Template::And') {
            my ($k,$v,$c) = ($template->{_keys}, $self->{values}, $template->{_constant_values});
            my $vn = 0;
            my $cn = 0;
            for my $key (@$k) {
                push @list, $key;
                if (substr($key,0,1) eq '-') {
                    push @list, $c->[$cn++];
                }
                else {
                    push @list, $v->[$vn++];
                }
            }
        }
        elsif ($template_class eq 'UR::BoolExpr::Template::Or') {
            my @sublist;
            my @u = $self->underlying_rules();
            for my $u (@u) {
                my @p = $u->_params_list;
                push @sublist, \@p;
            }
            @list = (-or => \@sublist);
        }
        elsif ($template_class->isa("UR::BoolExpr::PropertyComparison")) {
            @list = ($template->logic_detail => [@{$self->{values}}]);
        }
        \@list;
    };
    return @$list;
}

sub normalize {
    my $self = shift;

    my $rule_template = $self->template;
    
    if ($rule_template->{is_normalized}) {
        return $self;
    }
    my @unnormalized_values = $self->values();
    
    my $normalized = $rule_template->get_normalized_rule_for_values(@unnormalized_values);
    return unless defined $normalized;

    if (my $special = $self->{hard_refs}) {
        $normalized->{hard_refs} = $rule_template->_normalize_non_ur_values_hash($special);
    }
    return $normalized;
}

# a handful of places still use this
sub legacy_params_hash {
    my $self = shift;
        
    # See if we have one already.
    my $params_array = $self->{legacy_params_array};
    return { @$params_array } if $params_array;
    
    # Make one by starting with the one on the rule template
    my $rule_template = $self->template;
    my $params = { %{$rule_template->legacy_params_hash}, $self->params_list };
    
    # If the template has a _param_key, fill it in.
    if (exists $params->{_param_key}) {
        $params->{_param_key} = $self->id;
    }
    
    # This was cached above and will return immediately on the next call.
    # Note: the caller should copy this reference before making changes.
    $self->{legacy_params_array} = [ %$params ];
    return $params;
}

# TODO: these methods need a better home, since they are a cmdline/UI standard
sub filter_regex_for_string {
    return '^\s*(\w+)\s*(\@|\=|!=|=|\>|\<|~|!~|!\:|\:|\blike\b|\bbetween\b|\bin\b)\s*[\'"]?([^\'"]*)[\'"]?\s*$';
}

# TODO: these methods need a better home, since they are a cmdline/UI standard
sub resolve_for_string {
    my ($self, $subject_class_name, $filter_string, $usage_hints_string, $order_string, $page_string) = @_;

    my ($property, $op, $value);

    no warnings;
    
    my $filter_regex = $self->filter_regex_for_string();
    my @filters = map {
        unless (($property, $op, $value) = ($_ =~ /$filter_regex/)) {
            die "Unable to process filter $_\n";
        }
        if ($op eq '~') {
            $op = "like";
        } elsif ($op eq '!~') {
            $op = 'not like';
        }

        [$property, $op, $value]
    } split(/,/, $filter_string);

    my @hints = split(",",$usage_hints_string);
    my @order = split(",",$order_string);
    my @page  = split(",",$page_string);

    use warnings;
    return __PACKAGE__->_resolve_from_filter_array($subject_class_name, \@filters, \@hints, \@order, \@page);
}

sub _resolve_from_filter_array {
    my $class = shift;
    
    my $subject_class_name = shift;
    my $filters = shift;
    my $usage_hints = shift;
    my $order = shift;
    my $page = shift;

    my @rule_filters;
    
    my @keys;
    my @values;

    for my $fdata (@$filters) {
        my $rule_filter;
    
        # rule component
        my $key = $fdata->[0];
        my $value;
    
        # process the operator
        if ($fdata->[1] =~ /^!?(:|@|between|in)$/i) {
            
            my @list_parts;
            my @range_parts;
            
            if ($fdata->[1] eq "@") {
                # file path
                my $fh = IO::File->new($fdata->[2]);
                unless ($fh) {
                    die "Failed to open file $fdata->[2]: $!\n";
                }
                @list_parts = $fh->getlines;
                chomp @list_parts;
                $fh->close;
            }
            else {
                @list_parts = split(/\//,$fdata->[2]);
                @range_parts = split(/-/,$fdata->[2]);
            }
            
            if (@list_parts > 1) {
                my $op = ($fdata->[1] =~ /^!/ ? 'not in' : 'in'); 
                # rule component
                if (substr($key, -3, 3) ne ' in') {
                    $key = join(' ', $key, $op);
                }
                $value = \@list_parts;
                $rule_filter = [$fdata->[0],$op,\@list_parts];
            }
            elsif (@range_parts >= 2) {
                if (@range_parts > 2) {
                    if (@range_parts % 2) {
                        die "The \":\" operator expects a range sparated by a single dash: @range_parts ." . "\n";
                    }
                    else {
                        my $half = (@range_parts)/2;
                        $a = join("-",@range_parts[0..($half-1)]);
                        $b = join("-",@range_parts[$half..$#range_parts]);
                    }
                }
                elsif (@range_parts == 2) {
                    ($a,$b) = @range_parts;
                }
                else {
                    die 'The ":" operator expects a range sparated by a dash.' . "\n";
                }
                
                $key = $fdata->[0] . " between";
                $value = [$a, $b];
                $rule_filter = [$fdata->[0], "between", [$a, $b] ];
            }
            else {
                die 'The ":" operator expects a range sparated by a dash, or a slash-separated list.' . "\n";
            }
            
        }
        # this accounts for cases where value is null
        elsif (length($fdata->[2])==0) {
            if ($fdata->[1] eq "=") {
                $key = $fdata->[0];
                $value = undef;
                $rule_filter = [ $fdata->[0], "=", undef ];
            }
            else {
                $key = $fdata->[0] . " !=";
                $value = undef;
                $rule_filter = [ $fdata->[0], "!=", undef ];
            }
        }
        else {
            $key = $fdata->[0] . ($fdata->[1] and $fdata->[1] ne '='? ' ' . $fdata->[1] : '');
            $value = $fdata->[2];
            $rule_filter = [ @$fdata ];
        }
        
        push @keys, $key;
        push @values, $value;
    } 
    if ($usage_hints or $order or $page) {
        # todo: incorporate hints in a smarter way
        my %p;
        for my $key (@keys) {
            $p{$key} = shift @values;
        }
        return $class->resolve(
            $subject_class_name, 
            %p, 
            ($usage_hints   ? (-hints   => $usage_hints) : () ),
            ($order         ? (-order   => $order) : () ),
            ($page          ? (-page    => $page) : () ),
        ); 
    }
    else {
        return UR::BoolExpr->_resolve_from_subject_class_name_keys_and_values(
            subject_class_name => $subject_class_name,
            keys => \@keys,
            values=> \@values,
        );    
    }
    
}

sub _resolve_from_subject_class_name_keys_and_values {
    my $class = shift;
    
    my %params = @_;
    my $subject_class_name = $params{subject_class_name};
    my @values          = @{ $params{values} || [] };
    my @constant_values = @{ $params{constant_values} || [] };
    my @keys            = @{ $params{keys} || [] };
    die "unexpected params: " . Data::Dumper::Dumper(\%params) if %params;

    my $value_id = UR::BoolExpr::Util->values_to_value_id(@values);
    my $constant_value_id = UR::BoolExpr::Util->values_to_value_id(@constant_values);
    
    my $template_id = $subject_class_name . '/And/' . join(",",@keys) . "/" . $constant_value_id;
    my $rule_id = join($UR::BoolExpr::Util::id_sep,$template_id,$value_id);

    my $rule = __PACKAGE__->get($rule_id);

    $rule->{values} = \@values;

    return $rule;
}

1;

=pod

=head1 NAME

UR::BoolExpr - a "where clause" for objects 

=head1 SYNOPSIS
    
    my $o = Acme::Employee->create(
        ssn => '123-45-6789',
        name => 'Pat Jones',
        status => 'active', 
        start_date => UR::Context->current->now,
        payroll_category => 'hourly',
        boss => $other_employee,
    );    
        
    my $bx = Acme::Employee->define_boolexpr(
        'payroll_category'                  => 'hourly',
        'status'                            => ['active','terminated'],
        'name like'                         => '%Jones',
        'ssn matches'                       => '\d{3}-\d{2}-\d{4}',
        'start_date between'                => ['2009-01-01','2009-02-01'],
        'boss.name in'                      => ['Cletus Titus', 'Mitzy Mayhem'],
    );
    
    $bx->evaluate($o); # true 
    
    $bx->specifies_value_for('payroll_category') # true 
    
    $bx->value_for('payroll_cagtegory') # 'hourly'
        
    $o->payroll_category('salary');
    $bx->evaluate($o); # false

    # these could take either a boolean expression, or a list of params
    # from which it will generate one on-the-fly
    my $set     = Acme::Employee->define_set($bx);  # same as listing all of the params
    my @matches = Acme::Employee->get($bx);         # same as above, but returns the members 
       
    my $bx2 = $bx->reframe('boss');
    #'employees.payroll_category'            => 'hourly',
    #'employees.status'                      => ['active','terminated'],
    #'employees.name like'                   => '%Jones',
    #'employees.ssn matches'                 => '\d{3}-\d{2}-\d{4}',
    #'employees.start_date between'          => ['2009-01-01','2009-02-01'],
    #'name in'                               => ['Cletus Titus', 'Mitzy Mayhem'],

    my $bx3 = $bx->flatten();
    # any indirection in the params takes the form a.b.c at the lowest level
    # also 'payroll_category' might become 'pay_history.category', and 'pay_history.is_current' => 1 is added to the list
    # if this paramter has that as a custom filter


=head1 DESCRIPTION

A UR::BoolExpr object captures a set of match criteria for some class of object.

Calls to get(), create(), and define_set() all use this internally to objectify
their paramters.  If given a boolean expression object directly they will use it.
Otherwise they will construct one from the parameters given.

They have a 1:1 correspondence within the WHERE clause in an SQL statement where
RDBMS persistance is used.  They also imply the FROM clause in these cases,
since the query properties control which joins must be included to return
the matching object set.

=head1 REFLECTION

The data used to create the boolean expression can be re-extracted:

    my $c = $r->subject_class_name;
    # $c eq "GSC::Clone"

    my @p = $r->params_list;
    # @p = four items
    
    my %p = $r->params_list;
    # %p = two key value pairs

=head1 TEMPLATE SUBCLASSES

The template behind the expression can be of type ::Or, ::And or ::PropertyComparison.
These classes handle all of the operating logic for the expressions.

Each of those classes incapsulates 0..n of the next type in the list.  All templates
simplify to this level.  See L<UR::BoolExpr::Template> for details.

=head1 CONSTRUCTOR

=over 4

  my $bx = UR::BoolExpr->resolve('Some::Class', property_1 => 'value_1', ... property_n => 'value_n');
  my $bx1 = Some::Class->define_boolexpr(property_1 => value_1, ... property_n => 'value_n');
  my $bx2 = Some::Class->define_boolexpr('property_1 >' => 12345);

Returns a UR::BoolExpr object that can be used to perform tests on the given class and
properties.  The default comparison for each property is equality.  The last example shows
using greater-than operator for property_1.

=back

=head1 METHODS

=over 4

=item evaluate

    $bx->evaluate($object)

Returns true if the given object satisfies the BoolExpr


=item template_and_values

  ($template, @values) = $bx->template_and_values();

Returns the UR::BoolExpr::Template and list of the values for the given BoolExpr

=item is_subset_of

  $bx->is_subset_of($other_bx)

Returns true if the set of objects that matches this BoolExpr is a subset of
the set of objects that matches $other_bx.  In practice this means:

  * The subject class of $bx isa the subject class of $other_bx
  * all the properties from $bx also appear in $other_bx
  * the operators and values for $bx's properties match $other_bx

=item values

  @values = $bx->values

Return a list of the values from $bx.  The values will be in the same order
the BoolExpr was created from

=item value_for_id

  $id = $bx->value_for_id

If $bx's properties include all the ID properties of its subject class, 
C<value_for_id> returns that value.  Otherwise, it returns the empty list.
If the subject class has more than one ID property, this returns the value
of the composite ID.

=item specifies_value_for

  $bx->specifies_value_for('property_name');

Returns true if the filter list of $bx includes the given property name

=item value_for

  my $value = $bx->value_for('property_name');

Return the value for the given property

=item operator_for

  my $operator = $bx->operator_for('property_name');

Return a string for the operator of the given property.  A value of '' (the
empty string) means equality ("=").  Other possible values inclue '<', '>',
'<=', '>=', 'between', 'true', 'false', 'in', 'not <', 'not >', etc.

=item normalize

    $bx2 = $bx->normalize;

A boolen expression can be changed in incidental ways and still be equivalent.
This method converts the expression into a normalized form so that it can be
compared to other normalized expressions without incidental differences
affecting the comparision.

=item flatten

    $bx2 = $bx->flatten();

Transforms a boolean expression into a functional equivalent where
indirect properties are turned into property chains.

For instance, in a class with

    a => { is => "A", id_by => "a_id" },
    b => { via => "a", to => "bb" },
    c => { via => "b", to => "cc" },

An expression of:

    c => 1234
    
Becomes:

    a.bb.cc => 1234

In cases where one of the indirect properties includes a "where" clause,
the flattened expression would have an additional value for each element:

    a => { is => "A", id_by => "a_id" },
    b => { via => "a", to => "bb" },
    c => { via => "b", where ["xx" => 5678], to => "cc" },

An expression of:

    c => 1234
    
Becomes:

    a.bb.cc => 1234
    a.bb.xx => 5678



=item reframe

    $bx  = Acme::Order->define_boolexpr(status => 'active');
    $bx2 = $bx->reframe('customer');

The above will turn a query for orders which are active into a query for
customers with active orders, presuming an Acme::Order has a property called
"customer" with a defined relationship to another class.

=back

=head1 INTERNAL STRUCTURE

A boolean expression (or "rule") has an "id", which completely describes the rule in stringified form,
and a method called evaluate($o) which tests the rule on a given object.

The id is composed of two parts:
- A template_id. 
- A value_id.  

Nearly all real work delegates to the template to avoid duplication of cached details.

The template_id embeds several other properties, for which the rule delegates to it:
- subject_class_name, objects of which the rule can be applied-to
- subclass_name, the subclass of rule (property comparison, and, or "or")
- the body of the rule either key-op-val, or a list of other rules

For example, the rule GSC::Clone name=x,chromosome>y:
- the template_id embeds:
    subject_class_name = GSC::Clone
    subclass_name = UR::BoolExpr::And
    and the key-op pairs in sorted order: "chromosome>,name="
- the value_id embeds the x,y values in a special format

=head1 EXAMPLES


my $bool = $x->evaluate($obj);

my $t = GSC::Clone->template_for_params(
    "status =",
    "chromosome []",
    "clone_name like",
    "clone_size between"
);

my @results = $t->get_matching_objects(
    "active",
    [2,4,7],
    "Foo%",
    [100000,200000]
);

my $r = $t->get_rule($v1,$v2,$v3);

my $t = $r->template;

my @results = $t->get_matching_objects($v1,$v2,$v3);
my @results = $r->get_matching_objects();

@r = $r->underlying_rules();
for (@r) {
    print $r->evaluate($c1);
}

my $rt = $r->template();
my @rt = $rt->get_underlying_rule_templates();

$r = $rt->get_rule_for_values(@v);

=head1 SEE ALSO

UR(3), UR::Object(3), UR::Object::Set(3), UR::BoolExpr::Template(3)

=cut
