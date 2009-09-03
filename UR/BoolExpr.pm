package UR::BoolExpr;

use warnings;
use strict;
use Scalar::Util qw(blessed);
require UR;

our $VERSION = $UR::VERSION;;

# readable stringification
use overload ('""' => '__display_name__');

UR::Object::Type->define(
    class_name => 'UR::BoolExpr',
    composite_id_separator => $UR::BoolExpr::Util::id_sep,
    id_by => [
        template_id         => { type => 'BLOB' },
        value_id            => { type => 'BLOB' },
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

# override the UR/system display name
# this is used in stringification overload
sub __display_name__ {
    my $self = shift;
    my %b = $self->params_list;
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


sub values {
    my $self = shift;
    if ($self->{values}) {
        return @{ $self->{values}}
    }
    my $value_id = $self->value_id;    
    return unless defined($value_id) and length($value_id);
    return UR::BoolExpr::Util->value_id_to_values($value_id);
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
    # TODO: refactor to be more efficient
    my $self = shift;
    my $property_name = shift; 
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
    return [@$v];
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
    my @params;
    
    # Get the values
    # Add a key for each underlying rule
    my $rule_template = $self->template;
    my @keys_sorted = $rule_template->_underlying_keys;
    my @constant_values_sorted = $rule_template->_constant_values;
    my @values_sorted = $self->values;    
    if (my $non_ur_object_refs = $self->{non_ur_object_refs}) {
        my $n = 0;
        for my $key (@keys_sorted) {
            if (exists $non_ur_object_refs->{$key}) {
                $values_sorted[$n] = $non_ur_object_refs->{$key};
            }
            $n++;
        }
    }
    
    my ($v,$c) = (0,0);
    for (my $k=0; $k<@keys_sorted; $k++) {
        my $key = $keys_sorted[$k];                        
        if (substr($key,0,1) eq "_") {
            next;
        }
        elsif (substr($key,0,1) eq '-') {
            my $value = $constant_values_sorted[$c];
            push @params, $key, $value;        
            $c++;
        }
        else {
            my ($property, $op) = ($key =~ /^(\-*\w+)\s*(.*)$/);        
            unless ($property) {
                die;
            }
            my $value = $values_sorted[$v];
            if ($op) {
                if ($op ne "[]") {
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

# TODO: replace these with logical set operations

sub add_filter {
    my $self = shift;
    return __PACKAGE__->resolve($self->subject_class_name, $self->params_list, @_);
}

# FIXME this method seems misnamed.... it doesn't remove a filter on a rule, it returns 
# a new rule with all the same filters as the original one, less the one you specified
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

sub sub_classify {
    my ($self,$subclass_name) = @_;
    my ($t,@v) = $self->template_and_values();
    return $t->sub_classify($subclass_name)->get_rule_for_values(@v);
}

# flyweight constructor

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
        Carp::confess("Extra params found: @extra\n");
    }
    return $normalized_rule;
}

sub resolve_for_template_id_and_values {
    my ($class,$template_id, @values)  = @_;
    my $value_id = UR::BoolExpr::Util->values_to_value_id(@values);
    my $rule_id = $class->__meta__->resolve_composite_id_from_ordered_values($template_id,$value_id);
    $class->get($rule_id);
}

our $resolve_depth;
sub resolve {
    # Handle the case in which we've already processed the 
    # params into a rule.
    $resolve_depth++;
    Carp::confess("Deep recursion!") if $resolve_depth > 10;
    
    if ( @_ == 3 and ref($_[2]) and ref($_[2])->isa("UR::BoolExpr") ) {
        $resolve_depth--;
        return $_[2];
    }

    # This class.
    my $class = shift;

    # The class to which the parameters apply.
    my $subject_class = shift;
    my $subject_class_meta = $subject_class->__meta__;
    unless ($subject_class_meta) {
        die "No meta for $subject_class?!";
    }    

    my %subject_class_props = map {$_, 1}  ( $subject_class_meta->all_property_type_names);

    my @in_params;
    if (ref($_[0]) eq "HASH") {
	   @in_params = %{$_[0]};
    } else {
	   @in_params = @_;
    }
    
    # Handle the single ID.
    # Also handle the odd-number of params case, 
    # which is supported in older code.
    if (@in_params % 2 == 1) {
        unshift @in_params, "id";
    }

    # Split the params into keys and values
    my $count = @in_params;
    my (@keys,@values,@constant_values,$key,$value,$op,@extra,@non_ur_object_refs,$property_name, $operator);

    for(my $n = 0; $n < $count;) {
        $key = $in_params[$n++];
        $value = $in_params[$n++];

        if (substr($key,0,1) eq '-') {
            # these are keys whose values live in the rule template            
            push @keys, $key;
            push @constant_values, $value;
            next;
        }
        
        if (substr($key,0,1)  eq '_') {
            # skip the param
            next;
        } 
        
        if (!exists $subject_class_props{$key}) {
            if (my $pos = index($key,' ')) {
                $property_name = substr($key,0,$pos);
                $operator = substr($key,$pos+1);
                if (substr($operator,0,1) eq ' ') {
                   $operator =~ s/^\s+//; 
                }
            }
            else {
                $property_name = $key;
                $operator = '';
            }
            
            # account for the case where this parameter does
            # not match an actual property 
            if (!exists $subject_class_props{$property_name}) {
                if (my $attr = $subject_class_meta->property_meta_for_name($property_name)) {
                    die "Property found but not in array of properties?";
                }
                else {
                    push @extra, ($key => $value);
                    next;
                }
            }
        }
        else {
            $property_name = $key;
            $operator = '';
        }
        
        my $ref = ref($value);
        if($ref) {
            if ($ref eq "HASH") {
                if (
                    exists $value->{operator}
                    and exists $value->{value}
                ) {
                    $key .= " " . lc($value->{operator});
                    if (exists $value->{escape}) {
                        $key .= "-" . $value->{escape}
                    }
                    $value = $value->{value};
                }
            }
            elsif ($ref eq "ARRAY") {
                $key .= " []";
                
                # replace the arrayref
                $value = [ @$value ];
                
                # transform objects into IDs if applicable
                my $is_all_objects = 1;
                for (@$value) { 
                    unless (blessed($_)) {
                        $is_all_objects = 0;
                        last;
                    }
                }
                if ($is_all_objects) {
                    
                    my ($method) = ($key =~ /^(\w+)/);
                    if (my $subref = $subject_class->can($method) and $subject_class->isa("UR::Object")) {
                        for (@$value) { $_ =  $subref->($_) };
                    }
                }
    
                my $one_or_many = $subject_class_props{$property_name};
                unless (defined $one_or_many) {
                    die "$subject_class: '$property_name' ($key => $value)\n" . Data::Dumper::Dumper({ @_ });
                }
                
                my $is_many;
                my $data_type;
                my $property_meta = $subject_class_meta->property_meta_for_name($property_name);
                if ($property_meta) {
                    $is_many = $property_meta->is_many;
                    $data_type = $property_meta->data_type;
                }
                else {
                    if ($UR::initialized) {
                        Carp::confess("no meta for property $subject_class $property_name?\n");
                    }
                    else {
                        # this has to run during bootstrapping in 2 cases currently...
                        $is_many = $subject_class_meta->{has}{$property_name}{is_many};
                        $data_type = $subject_class_meta->{has}{$property_name}{data_type};
                    }
                }
                $data_type ||= '';  # avoid a warning about undefined below
                if ($data_type ne 'ARRAY' and !$is_many) {
                    no warnings;
    
                    # sort and replace the arrayref
                    @$value = (
                        sort { $a <=> $b or $a cmp $b } 
                        @$value
                    );         
                    
                    # identify duplicates
                    my $last = $value; # a safe value which can't be in the list
                    for (@$value) {
                        if ($_ eq $last) {
                            $last = $value;
                            last;
                        }
                        $last = $_;
                    }
    
                    # only fix duplicates if they were found                    
                    if ($last eq $value) {
                        my $buffer;
                        @$value =
                            map {
                                $buffer = $last;
                                $last = $_;
                                ($_ eq $buffer ? () : $_)
                            }
                            @$value;
                    }
                }
            }
            elsif (blessed($value)) {
                my $property_type = $subject_class_meta->property_meta_for_name($key);
                unless ($property_type) {
                    for my $class_name ($subject_class_meta->ancestry_class_names) {
                        my $class_object = $class_name->__meta__;
                        $property_type = $subject_class_meta->property_meta_for_name($key);
                        last if $property_type;
                    }
                    unless ($property_type) {
                        die "No property type found for $subject_class $key?";
                    }
                }

                if ($property_type->is_delegated) {
                    my $property_meta = $subject_class_meta->property_meta_for_name($key);
                    unless ($property_meta) {
                        die "Failed to find meta for $key on " . $subject_class_meta->class_name . "?!";
                    }
                    my @joins = $property_meta->get_property_name_pairs_for_join();
                    for my $join (@joins) {
                        my ($my_method, $their_method) = @$join;
                        push @keys, $my_method;
                        push @values, $value->$their_method;
                    }

                    #
                    # WARNING WARNING looping early before we get to the bottom!
                    next;
                    #
                    #
                }
                elsif ($value->isa($property_type->data_type)) {
                    push @non_ur_object_refs, $key, $value;
                }
                elsif ($value->can($key)) {
                    $value = $value->$key;
                }
                else {
                    die "Incorrect data type " . ref($value) . " for $subject_class property $key!";    
                }
            }
        }
        push @keys, $key;
        push @values, $value;
    }

    my $value_id = UR::BoolExpr::Util->values_to_value_id(@values);
    my $constant_value_id = UR::BoolExpr::Util->values_to_value_id(@constant_values);
    
    my $template_id = $subject_class . '/And/' . join(",",@keys) . "/" . $constant_value_id;
    my $rule_id = join($UR::BoolExpr::Util::id_sep,$template_id,$value_id);

    my $rule = __PACKAGE__->get($rule_id);

    $rule->{values} = \@values;

    if (@non_ur_object_refs) {
        $rule->{non_ur_object_refs} = { @non_ur_object_refs };
    }

    $resolve_depth--;
    if (wantarray) {
        return ($rule, @extra);
    } elsif (@extra && defined wantarray) {
        Carp::confess("Unknown parameters for $subject_class: @extra");
    }
    else {
        return $rule;
    }
}

sub normalize {
    my $self = shift;
    
    my $rule_template = $self->template;
    
    if ($rule_template->{is_normalized}) {
        return $self;
    }
    
    my @unnormalized_values = $self->values();
    
    return $rule_template->get_normalized_rule_for_values(@unnormalized_values);
}

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

sub resolve_for_string {
    my ($self, $subject_class_name, $filter_string, $usage_hints_string, $order_string, $page_string) = @_;

    my ($property, $op, $value);
    no warnings;
    my @filters = map {
        unless (
            ($property, $op, $value) =
            ($_ =~ /^\s*(\w+)\s*(\@|\=|!=|=|\>|\<|~|!~|\:|\blike\b)\s*['"]?([^'"]*)['"]?\s*$/)
        ) {
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
        if ($fdata->[1] =~ /^(:|@)$/i) {
            
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
                # rule component
                $key .= " []";
                $value = \@list_parts;
        
                $rule_filter = [$fdata->[0],"[]",\@list_parts];
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

    #$DB::single = $DB::stopper;
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
        start_date => UR::Time->now,
        payroll_category => 'hourly',
    );    
        
    my $bx = Acme::Employee->define_boolexpr(
        payroll_category => 'hourly',
        status => ['active','terminated'],
        'name like' => '%Jones',
        'ssn matches' => '\d{3}-\d{2}-\d{4}',
        'start_date between' => ['2009-01-01','2009-02-01'],
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

The data used to create the rule can be re-extracted:

    my $c = $r->subject_class_name;
    # $c eq "GSC::Clone"

    my @p = $r->params_list;
    # @p = four items
    
    my %p = $r->params_list;
    # %p = two key value pairs

=head1 SUBCLASSES

 The ::Rule class is abstract, but the primary constructor (resolve_normalized_rule_for_class_and_params),
 automatically returns rules of the correct subclass for the specified parameters.  
 
 Currently it always returns a ::Rule::And object, which is the composite of all key-value pairs passed-in.

=item ::Rule::And

 Rules of this type contain a list of other rules, ALL of which must be true for the given rule to be true.
 Inherits from the intermediate class ::Rule::Composite.
 
=item ::Rule::Or

 Rules of this type contain a list of other rules, ANY of which must be true for the given rule to be true.
 Inherits from the intermediate class ::Rule::Composite.

=item ::Rule::PropertyComparison

 Rules of this type compare a single property on the subject, using a specific comparison operator,
 against a specific value (or value set for certain operators).  This is the low-level non-composite rule.

=head1 INTERNAL STRUCTURE

A rule has an "id", which completely describes the rule in stringified form,
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
