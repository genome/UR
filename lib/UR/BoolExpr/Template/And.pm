package UR::BoolExpr::Template::And;
use warnings;
use strict;
require UR;
our $VERSION = "0.31"; # UR $VERSION;;

UR::Object::Type->define(
    class_name      => __PACKAGE__,
    is              => ['UR::BoolExpr::Template::Composite'],
);

sub _flatten_bx {
    my ($class, $bx) = @_;
    my $template = $bx->template;
    my ($flattened_template, @extra_values) = $template->_flatten(@_);
    my $flattened_bx;
    if (not @extra_values) {
        # optimized
        my $flattened_bx_id = $flattened_template->id . $UR::BoolExpr::Util::id_sep . $bx->value_id;
        $flattened_bx = UR::BoolExpr->get($flattened_bx_id);
        $flattened_bx->{'values'} = $bx->{'values'} unless $flattened_bx->{'values'};
    }
    else {
        $flattened_bx = $flattened_template->get_rule_for_values($bx->values, @extra_values);    
    }
    return $flattened_bx;
}

sub _reframe_bx {
    my ($class, $bx, $in_terms_of_property_name) = @_;
    my $template = $bx->template;
    my ($reframed_template, @extra_values) = $template->_reframe($in_terms_of_property_name);
    my $reframed_bx;
    if (@extra_values == 0) {
        my $reframed_bx_id = $reframed_template->id . $UR::BoolExpr::Util::id_sep . $bx->value_id;
        $reframed_bx = UR::BoolExpr->get($reframed_bx_id);
        $reframed_bx->{'values'} = $bx->{'values'} unless $reframed_bx->{'values'};
    }
    else {
        my @values = ($bx->values, @extra_values);
        $reframed_bx = $reframed_template->get_rule_for_values(@values);
    }
    return $reframed_bx;
}

sub _flatten {
    my $self = $_[0];
     
    if ($self->{flatten}) {
        return @{ $self->{flatten} }
    }

    $DB::single = 1;

    my @old_keys = @{ $self->_keys };
    my $old_property_meta_hash = $self->_property_meta_hash;

    my $class_meta = $self->subject_class_name->__meta__;
    
    my @new_keys;
    my @extra_keys;
    my @extra_values;
    
    my $old_constant_values;
    my @new_constant_values;

    my $found_unflattened_params = 0;
    while (my $key = shift @old_keys) {
        my $name = $key;
        $name =~ s/ .*//;
        if (substr($name,0,1) ne '-') {
            my $mdata = $old_property_meta_hash->{$name};
            my ($value_position, $operator) = @$mdata{'value_position','operator'};
            
            my ($flat, $add_keys, $add_values) = $class_meta->_flatten_property_name($name); 
            $found_unflattened_params = 1 if $flat ne $name or @$add_keys or @$add_values;

            $flat .= ' ' . $operator if $operator and $operator ne '=';
            push @new_keys, $flat;
            
            push @extra_keys, @$add_keys;
            push @extra_values, @$add_values;
        }
        else {
            $DB::single =1;
            push @new_keys, $key;
            $old_constant_values ||= [ @{ $self->_constant_values } ];
            my $old_value = shift @$old_constant_values;
            my $new_value = [];
            for my $part (@$old_value) {
                my ($flat, $add_keys, $add_values) = $class_meta->_flatten_property_name($part); 
                $found_unflattened_params = 1 if $flat ne $name or @$add_keys or @$add_values;
                push @$new_value, $flat;

                push @extra_keys, @$add_keys;
                push @extra_values, @$add_values;
            }
            push @new_constant_values, $new_value;
        }
    }

    my $constant_values;
    if ($old_constant_values) {
        # some -* keys were found above, and we flattened the value internals
        $constant_values = \@new_constant_values;
    }
    else {
        # no -* keys, just re-use the empty arrayref
        $constant_values = $self->_constant_values;
    }

    if ($found_unflattened_params or @extra_keys) {
        if (@extra_keys) {
            # there may be duplication between these and the primary joins
            # or each other
            my %keys_seen = map { $_ => 1 } @new_keys;
            my @nodup_extra_keys;
            my @nodup_extra_values;
            while (my $extra_key = shift @extra_keys) {
                my $extra_value = shift @extra_values;
                unless ($keys_seen{$extra_key}) {
                    push @nodup_extra_keys, $extra_key;
                    push @nodup_extra_values, $extra_value;
                    $keys_seen{$extra_key} = 1;
                }
            }
            push @new_keys, @nodup_extra_keys;
            @extra_values = @nodup_extra_values
        }
        my $flat = UR::BoolExpr::Template::And->_fast_construct(
            $self->subject_class_name, 
            \@new_keys, 
            $constant_values,     
        );
        $self->{flatten} = [$flat,@extra_values];
        return ($flat, @extra_values);
    }
    else {
        # everything was already flat, just remember this so you DRY
        $self->{flatten} = [$self];
        Scalar::Util::weaken($self->{flatten}[0]);
        return $self
    }
}

sub _reframe {
    my $self = shift;
    my $in_terms_of_property_name = shift;
    $DB::single = 1;
    # determine the from_class, to_class, and path_back
    my $from_class = $self->subject_class_name;
    my $cmeta = $self->subject_class_name->__meta__;
    my @pmeta = $cmeta->property_meta_for_name($in_terms_of_property_name);
    unless (@pmeta) {
        Carp::confess("Failed to find property $in_terms_of_property_name on $from_class.  Cannot reframe $self!");  
    }
    my @reframe_path_forward = map { $_->_resolve_join_chain } @pmeta;
    my $path_back    = join('.', map { $_->{foreign_name_for_source} } reverse @reframe_path_forward);
    my $to_class = $reframe_path_forward[-1]{foreign_class};

    # translate all of the old properties to use the path back to the original class
    my ($flat,@extra_values) = $self->_flatten;
    my @old_property_names = $flat->_property_names;
    my $old_property_meta_hash = $flat->_property_meta_hash;

    my $reframer = sub {
        my $old_name = $_[0];
        # uses: @reframe_path_forward from above in this closure

        # get back to the original object
        my @reframe_path_back = reverse @reframe_path_forward;

        # then forward to the property related to it
        my @filter_path_forward = split('\.',$old_name);

        # if the end of the path back matches the beginning of the path 
        # to the property in the expression unneeded steps (beyond 1)
        my $new_key;
        while (1) {
            unless (@reframe_path_back) {
                last;
            }
            unless (@filter_path_forward) {
                last;
            }
            my $last_name_back = $reframe_path_back[-1]{source_name_for_foreign};
            my $first_name_forward = $filter_path_forward[0];
            if ($last_name_back ne $first_name_forward) {
                # found a difference
                last;
            }
            else {
                # the last step back matches the first step to the property
                if (@reframe_path_back == 1 and @filter_path_forward == 1) {
                    # just keep one of the identical pair
                    shift @filter_path_forward;
                }
                else {
                    # remove both (if one is empty this is no problem)
                    pop @reframe_path_back;
                    shift @filter_path_forward;
                }
            }
        }
        
        $new_key = join('.', map { $_->{foreign_name_for_source} } @reframe_path_back);
        $new_key = join('.', ($new_key ? $new_key : ()), @filter_path_forward);

        return $new_key;
    };

    
    # this is only set below if we find any -* keys
    my $old_constant_values;

    my @new_keys;
    my @new_constant_values;    

    while (@old_property_names) {
        my $old_name = shift @old_property_names;
        if (substr($old_name,0,1) ne '-') {
            # a regular property
            my $mdata = $old_property_meta_hash->{$old_name};
            my ($value_position, $operator) = @$mdata{'value_position','operator'};
            
            my $new_key = $reframer->($old_name);

            $new_key .= ' ' . $operator if $operator and $operator ne '=';
            push @new_keys, $new_key;
        }
        else {
            $DB::single = 1;
            # this key is not a property, it's a special key like -order_by or -group_by
            unless ($old_name =~ /^-{order|group}_by/ or $old_name =~ /^-{hint|recurse}/) {
                Carp::confess("no support yet for $old_name in bx reframe()!");
            }

            push @new_keys, $old_name;

            unless ($old_constant_values) {
                $old_constant_values = [ @{ $flat->_constant_values } ];
            }

            my $old_value = shift @$old_constant_values;
            my $new_value = [];
            for my $part (@$old_value) {
                my $reframed_part = $reframer->($part);
                push @$new_value, $reframed_part;
            }
            push @new_constant_values, $new_value;
        }
    }


    my $constant_values;    
    if (@new_constant_values) {
        $constant_values = \@new_constant_values;
    }
    else {
        $constant_values = $flat->_constant_values; # re-use empty immutable arrayref
    }

    my $reframed = UR::BoolExpr::Template::And->_fast_construct(
        $to_class, 
        \@new_keys, 
        $constant_values,     
    );

    return $reframed, @extra_values;
}

sub _template_for_grouped_subsets {
    my $self = shift;
    my $group_by = $self->group_by;
    die "rule template $self->{id} has no -group_by!?!?" unless $group_by;

    my @base_property_names = $self->_property_names;
    for (my $i = 0; $i < @base_property_names; $i++) {
        my $operator = $self->operator_for($base_property_names[$i]);
        if ($operator ne '=') {
            $base_property_names[$i] .= " $operator";
        }
    }

    my $template = UR::BoolExpr::Template->get_by_subject_class_name_logic_type_and_logic_detail(
        $self->subject_class_name,
        'And',
        join(",", @base_property_names, @$group_by),
    );

    return $template;
}

sub _variable_value_count {
    my $self = shift;
    my $k = $self->_underlying_keys;
    my $v = $self->_constant_values;
    if ($v) {
        $v = scalar(@$v);
    }
    else {
        $v = 0;
    }
    return $k-$v;
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
    my $subject_class_name = $self->subject_class_name;
    return map {                
            UR::BoolExpr::Template::PropertyComparison
                ->_get_for_subject_class_name_and_logic_detail(
                    $subject_class_name,
                    $_
                );
        } @underlying_keys;
}

sub specifies_value_for {
    my ($self, $property_name) = @_;
    Carp::confess('Missing required parameter property_name for specifies_value_for()') if not defined $property_name;
    my @underlying_templates = $self->get_underlying_rule_templates();
    foreach ( @underlying_templates ) {
        return 1 if $property_name eq $_->property_name;
    }
    return;
}

sub evaluate_subject_and_values {
    my $self = shift;
    my $subject = shift;

    return unless (ref($subject) && $subject->isa($self->subject_class_name));

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

sub params_list_for_values {
    # This is the reverse of the bulk of resolve.
    # It returns the params in list form, directly coercable into a hash if necessary.
    # $r = UR::BoolExpr->resolve($c1,@p1);
    # ($c2, @p2) = ($r->subject_class_name, $r->params_list);
    
    my $rule_template = shift;
    my @values_sorted = @_;
    
    my @keys_sorted = $rule_template->_underlying_keys;
    my $constant_values = $rule_template->_constant_values;
    
    my @params;
    my ($v,$c) = (0,0);
    for (my $k=0; $k<@keys_sorted; $k++) {
        my $key = $keys_sorted[$k];                        
        #if (substr($key,0,1) eq "_") {
        #    next;
        #}
        #elsif (substr($key,0,1) eq '-') {
        if (substr($key,0,1) eq '-') {
            my $value = $constant_values->[$c];
            push @params, $key, $value;        
            $c++;
        }
        else {
            my ($property, $op) = ($key =~ /^(\-*[\w\.]+)\s*(.*)$/);        
            unless ($property) {
                die "bad key $key in @keys_sorted";
            }
            my $value = $values_sorted[$v];
            if ($op) {
                if ($op ne "in") {
                    if ($op =~ /^(.+)-(.+)$/) {
                        $value = { operator => $1, value => $value, escape => $2 };
                    }
                    else {
                        $value = { operator => $op, value => $value };
                    }
                }
            }
            push @params, $property, $value;
            $v++;
        }
    }

    return @params; 
}

sub _fast_construct {
    my ($class,
        $subject_class_name,    # produces subject class meta
        $keys,                  # produces logic detail
        $constant_values,       # produces constant value id
        
        $logic_detail,          # optional, passed by get
        $constant_value_id,     # optional, passed by get
        $subject_class_meta,    # optional, passed by bx
    ) = @_;

    my $logic_type = 'And';    
    
    $logic_detail       ||= join(",",@$keys);
    $constant_value_id  ||= UR::BoolExpr::Util->values_to_value_id(@$constant_values);
   
    my $id = join('/',$subject_class_name,$logic_type,$logic_detail,$constant_value_id);  
    my $self = $UR::Object::rule_templates->{$id};
    return $self if $self;  

    $subject_class_meta ||= $subject_class_name->__meta__;    

    # See what properties are id-related for the class
    my $cache = $subject_class_meta->{cache}{'UR::BoolExpr::Template::get'} ||= do {
        my $id_related = {};
        my $id_translations = [];
        my $id_pos = {};
        my $id_prop_is_real;  # true if there's a property called 'id' that's a real property, not from UR::Object
        for my $iclass ($subject_class_name, $subject_class_meta->ancestry_class_names) {
            last if $iclass eq "UR::Object";
            next unless $iclass->isa("UR::Object");
            my $iclass_meta = $iclass->__meta__;
            my @id_props = $iclass_meta->id_property_names;
            next unless @id_props;
            $id_prop_is_real = 1 if (grep { $_ eq 'id'} @id_props);
            next if @id_props == 1 and $id_props[0] eq "id" and !$id_prop_is_real;
            push @$id_translations, \@id_props;
            @$id_related{@id_props} = @id_props;
            @$id_pos{@id_props} = (0..$#id_props);
        }
        [$id_related,$id_translations,$id_pos];
    };
    my ($id_related,$id_translations,$id_pos) = @$cache;

    my @keys = @$keys;
    my @constant_values = @$constant_values;

    # Make a hash to quick-validate the params for duplication
    no warnings; 
    my %check_for_duplicate_rules;
    for (my $n=0; $n < @keys; $n++) {
        next if (substr($keys[$n],0,1) eq '-');
        my $pos = index($keys[$n],' ');
        if ($pos != -1) {
            my $property = substr($keys[$n],0,$pos);
            $check_for_duplicate_rules{$property}++;
        }
        else {
            $check_for_duplicate_rules{$keys[$n]}++;
        }
    }

    # each item in this list mutates the initial set of key-value pairs
    my $extenders = [];
    
    # add new @$extenders for class-specific characteristics
    # add new @keys at the same time
    # flag keys as removed also at the same time

    # note the positions for each key in the "original" rule
    # by original, we mean the original plus the extensions from above
    #
    my $id_position = undef;
    my $var_pos = 0;
    my $const_pos = 0;
    my $property_meta_hash = {};        
    my $property_names = [];
    for my $key (@keys) {
        if (substr($key,0,1) eq '-') {
            $property_meta_hash->{$key} = {
                name => $key,
                value_position => $const_pos
            };
            $const_pos++;
        }
        else {
            my ($name, $op) = ($key =~ /^(.+?)\s+(.*)$/);
            $name ||= $key;
            if ($name eq 'id') {
                $id_position = $var_pos;
            }                
            $property_meta_hash->{$name} = {
                name => $name,
                operator => $op,
                value_position => $var_pos
            };        
            $var_pos++;
            push @$property_names, $name;
        }    
    }

    # Note whether there are properties not involved in the ID
    # Add value extenders for any cases of id-related properties,
    # or aliases.
    my $original_key_count = @keys;
    my $id_only = 1;
    my $partial_id = 0;        
    my $key_op_hash = {};
    if (@$id_translations and @{$id_translations->[0]} == 1) {
        # single-property ID
        ## use Data::Dumper;
        ## print "single property id\n". Dumper($id_translations);
        my ($key_pos,$key,$property,$op,$x);

        # Presume we are only getting id properties until another is found.
        # If a multi-property is partially specified, we'll zero this out too.
        
        for ($key_pos = 0; $key_pos < $original_key_count; $key_pos++) {
            $key = $keys[$key_pos];

            my ($property, $op) = ($key =~ /^(.+?)\s+(.*)$/);
            $property ||= $key;
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
                    push @$extenders, [ [$key_pos], undef, $keys[-1] ];
                    $key_op_hash->{$alias->[0]} ||= {};
                    $key_op_hash->{$alias->[0]}{$op}++;
                    ## print ">> extend for @$alias with op $op.\n";
                }
                unless ($op =~ m/^(=|eq|in|\[\]|)$/) {
                    $id_only = 0;
                }
            }    
            elsif (substr($key,0,1) ne '-') {
                $id_only = 0;
                ## print "non id single property $property on $subject_class\n";
            }
        }            
    }
    else {
        # multi-property ID
        ## print "multi property id\n". Dumper($id_translations);
        my ($key_pos,$key,$property,$op);
        my %id_parts;
        for ($key_pos = 0; $key_pos < $original_key_count; $key_pos++) {
            $key = $keys[$key_pos];
            next if substr($key,0,1) eq '-';

            my ($property, $op) = ($key =~ /^(.+?)\s+(.*)$/);
            $property ||= $key;
            $op ||= '';
            $op =~ s/^\s+// if $op;
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
                        push @$extenders, [ [$key_pos], "resolve_ordered_values_from_composite_id", @new_keys ];
                        for (@$alias) {
                            $key_op_hash->{$_} ||= {};
                            $key_op_hash->{$_}{$op}++;
                        }
                        # print ">> extend for @$alias with op $op.\n";
                    }
                }
            }    
            elsif ($id_related->{$property}) {
                if ($op eq "" or $op eq "eq" or $op eq "=" or $op eq 'in') {
                    $id_parts{$id_pos->{$property}} = $key_pos;                        
                }
                else {
                    # We're doing some sort of gray-area comparison on an ID                        
                    # field, and though we could possibly resolve an ID
                    # from things like an 'in' op, it's more than we've done
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
                        push @$extenders, [ [@id_parts{@id_pos}], "resolve_composite_id_from_ordered_values", 'id' ]; #TODO was this correct?
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
        } else {
            $id_only = 0;
            $partial_id = 0;
        }
    }
    
    # Determine the positions of each key in the parameter list.
    # In actuality, the position of the key's value in the @values or @constant_values array,
    # depending on whether it is a -* key or not.
    my %key_positions;
    my $vpos = 0;
    my $cpos = 0;
    for my $key (@keys) {
        $key_positions{$key} ||= [];
        if (substr($key,0,1) eq '-') {
            push @{ $key_positions{$key} }, $cpos++;    
        }
        else {
            push @{ $key_positions{$key} }, $vpos++;    
        }
    }

    # Sort the keys, and make an arrayref which will 
    # re-order the values to match.
    my $last_key = '';
    my @keys_sorted = map { $_ eq $last_key ? () : ($last_key = $_) } sort @keys;


    my $normalized_positions_arrayref = [];
    my $constant_value_normalized_positions = [];
    my $recursion_desc = undef;
    my $hints = undef;
    my $order_by = undef;
    my $group_by = undef;
    my $page = undef;
    my $limit = undef;
    my $aggregate = undef;
    my @constant_values_sorted;

    for my $key (@keys_sorted) {
        my $pos_list = $key_positions{$key};
        my $pos = pop @$pos_list;
        if (substr($key,0,1) eq '-') {
            push @$constant_value_normalized_positions, $pos;
            my $constant_value = $constant_values[$pos];
            push @constant_values_sorted, $constant_value;

            if ($key eq '-recurse') {
                $recursion_desc = $constant_value;
            }
            elsif ($key eq '-hints' or $key eq '-hint') {
                $hints = $constant_value; 
            }
            elsif ($key eq '-order_by' or $key eq '-order') {
                $order_by = $constant_value;
            }
            elsif ($key eq '-group_by' or $key eq '-group') {
                $group_by = $constant_value;
            }
            elsif ($key eq '-page') {
                $page = $constant_value;
            }
            elsif ($key eq '-limit') {
                $limit = $constant_value;
            }
            elsif ($key eq '-aggregate') {
                $aggregate = $constant_value;
            }
            else {
                Carp::croak("Unknown special param '$key'.  Expected one of: @UR::BoolExpr::Template::meta_param_names");
            }
        }
        else {
            push @$normalized_positions_arrayref, $pos;
        }
    }

    if (defined($hints) and ref($hints) ne 'ARRAY') {
        Carp::croak('-hints of a rule must be an arrayref of property names');
    }

    my $matches_all = scalar(@keys_sorted) == scalar(@constant_values);
    $id_only = 0 if ($matches_all);

    # these are used to rapidly turn a bx used for querying into one
    # suitable for object construction
    my @ambiguous_keys;
    my @ambiguous_property_names;
    for (my $n=0; $n < @keys; $n++) {
        next if substr($keys[$n],0,1) eq '-';
        my ($property, $op) = ($keys[$n] =~ /^(.+?)\s+(.*)$/);
        $property ||= $keys[$n];
        $op ||= '';
        $op =~ s/^\s+// if $op;
        if ($op and $op ne 'eq' and $op ne '==') {
            push @ambiguous_keys, $keys[$n];
            push @ambiguous_property_names, $property;
        }
    }

    # Determine the rule template's ID.
    # The normalizer will store this.  Below, we'll
    # find or create the template for this ID.
    my $normalized_constant_value_id = (scalar(@constant_values_sorted) ? UR::BoolExpr::Util->values_to_value_id(@constant_values_sorted) : $constant_value_id);
    my $normalized_id = UR::BoolExpr::Template->__meta__->resolve_composite_id_from_ordered_values($subject_class_name, "And", join(",",@keys_sorted), $normalized_constant_value_id);

    $self = bless {
        id                              => $id,
        subject_class_name              => $subject_class_name,
        logic_type                      => $logic_type,
        logic_detail                    => $logic_detail,
        constant_value_id               => $constant_value_id,
        normalized_id                   => $normalized_id,
        
        # subclass specific
        id_position                     => $id_position,        
        is_id_only                      => $id_only,
        is_partial_id                   => $partial_id,
        is_unique                       => undef, # assigned on first use
        matches_all                     => $matches_all,
        
        key_op_hash                     => $key_op_hash,
        _property_names_arrayref        => $property_names,
        _property_meta_hash             => $property_meta_hash,
        
        recursion_desc                  => $recursion_desc,
        hints                           => $hints,
        order_by                        => $order_by,
        page                            => $page,
        group_by                        => $group_by,
        limit                           => $limit,
        aggregate                       => $aggregate,
        
        is_normalized                   => ($id eq $normalized_id ? 1 : 0),
        normalized_positions_arrayref   => $normalized_positions_arrayref,
        constant_value_normalized_positions_arrayref => $constant_value_normalized_positions,
        normalization_extender_arrayref => $extenders,
        
        num_values                      => scalar(@$keys),
        
        _keys                           => \@keys,    
        _constant_values                => $constant_values,

        _ambiguous_keys                 => (@ambiguous_keys ? \@ambiguous_keys : undef),
        _ambiguous_property_names       => (@ambiguous_property_names ? \@ambiguous_property_names : undef),

    }, 'UR::BoolExpr::Template::And';

    $UR::Object::rule_templates->{$id} = $self;  
    return $self;
}


1;

=pod

=head1 NAME

UR::BoolExpr::And -  a rule which is true if ALL the underlying conditions are true 

=head1 SEE ALSO

UR::BoolExpr;(3)

=cut 
