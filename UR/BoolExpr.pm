
=head1 NAME

UR::BoolExpr - a boolean expression functional on any UR::Object of a given class

=cut

package UR::BoolExpr;

our $VERSION = '0.1';

use warnings;
use strict;

use Scalar::Util qw(blessed);
use UR;

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

# All of the meta-data is not in the meta class yet.

UR::Object::Type->define(
    class_name => 'UR::BoolExpr',
    composite_id_separator => $id_sep,
    id_by => [
        rule_template_id    => { type => 'BLOB' },
        value_id            => { type => 'BLOB' },
    ],
    has => [
        rule_template       => { is => 'UR::BoolExpr::Template', id_by => 'rule_template_id' },
        subject_class_name  => { via => 'rule_template' },
        logic_type          => { via => 'rule_template' },
        logic_detail        => { via => 'rule_template' },
        num_values          => { via => 'rule_template' },
        is_normalized       => { via => 'rule_template' },
        is_id_only          => { via => 'rule_template' }, 
    ],
    is_transactional => 0,
);

*get_rule_template = \&rule_template;

# These versions of the id accessors keep the values underlying the ID from getting their own hash keys.
# Update the id accessors in general to do this for composite ids?

sub decomposed_id {
     my $self = shift;
     my $id = $self->id;
     my $pos = index($id,$id_sep);
     return (substr($id,0,$pos), substr($id,$pos+1));
}

sub composite_id {
    shift;
    return join($id_sep,@_);
}

# Behind the id properties:

*get_rule_template_and_values = \&get_template_and_values;

sub get_template_and_values {
    my $self = shift;
    my ($template_id, $value_id) = $self->decomposed_id;
    return (UR::BoolExpr::Template->get($template_id), $self->value_id_to_values($value_id));
}


sub get_values {
    my $self = shift;
    if ($self->{values}) {
        return @{ $self->{values}}
    }
    my $value_id = $self->value_id;    
    return unless defined($value_id) and length($value_id);
    return $self->value_id_to_values($value_id);
}

sub specified_value_for_id {
    my $self = shift;
    my $t = $self->get_rule_template;
    my $position = $self->get_rule_template->id_position;
    $position = $self->get_rule_template->id_position;
    return unless defined $position;
    return $self->specified_value_for_position($position);
}


sub specified_value_for_position {
    my ($self, $pos) = @_;
    return ($self->get_values)[$pos];    
}

sub operator_for_property_name {
    my $self = shift;
    my $t = $self->get_rule_template;
    return $t->operator_for_property_name(@_);
}


# The primary function: evaluate a subject object as matching the rule or not.

sub evaluate {
    my $self = shift;
    my $subject = shift;
    my $template = $self->get_rule_template;
    my @values = $self->get_values;
    return $template->evaluate_subject_and_values($subject,@values);
}

# Examine the rule
# This only works with the composite "And" rule comparing properties.

sub get_underlying_rules { # refactor: what does this mean for non-composites?
    my $self = shift;    
    my @values = $self->get_values;    
    return $self->get_rule_template->get_underlying_rules_for_values(@values);
}

sub specifies_value_for_property_name {
    my $self = shift;
    my $rule_template = $self->get_rule_template;
    return $rule_template->specifies_value_for_property_name(@_);
}

sub specified_operator_for_property_name {
    my $self = shift;
    my $property_name = shift; 
    my $h = $self->legacy_params_hash;
    my $v = $h->{$property_name};
    return "=" unless ref($v);
    return $v->{operator} if ref($v) eq "HASH";
    return "[]";
}

sub specified_value_for_property_name {
    # TODO: refactor to be more efficient
    my $self = shift;
    my $property_name = shift; 
    my $h = $self->legacy_params_hash;
    my $v = $h->{$property_name};
    return $v unless ref($v);
    return $v->{value} if ref($v) eq "HASH";
    return [@$v];
}

sub value_position_for_property_name {
    $_[0]->get_rule_template()->value_position_for_property_name($_[1]);
}

# De-compose the rule back into its original form.

sub params_list {
    # This is the reverse of the bulk of resolve_for_class_and_params.
    # It returns the params in list form, directly coercable into a hash if necessary.
    # $r = UR::BoolExpr->resolve_for_class_and_params($c1,@p1);
    # ($c2, @p2) = ($r->subject_class_name, $r->params_list);
    
    my $self = shift;
    my @params;
    
    # Get the values
    # Add a key for each underlying rule
    my $rule_template = $self->get_rule_template;
    my @keys_sorted = $rule_template->_underlying_keys;
    my @constant_values_sorted = $rule_template->_constant_values;
    my @values_sorted = $self->get_values;    
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
    return __PACKAGE__->resolve_for_class_and_params($self->subject_class_name, $self->params_list, @_);
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
    return __PACKAGE__->resolve_for_class_and_params($self->subject_class_name, @new_params_list);
}

sub sub_classify {
    my ($self,$subclass_name) = @_;
    my ($t,@v) = $self->get_rule_template_and_values();
    return $t->sub_classify($subclass_name)->get_rule_for_values(@v);
}

# flyweight constructor

sub get {
    my $rule_id = pop;
    my $rule = $UR::Object::rules{$rule_id};
    return $rule if $rule;
    my $pos = index($rule_id,$id_sep);
    my ($template_id,$value_id) = (substr($rule_id,0,$pos), substr($rule_id,$pos+1));
    $rule = { id => $rule_id, rule_template_id => $template_id, value_id => $value_id };    
    bless ($rule, "UR::BoolExpr");
    $UR::Object::rules{$rule_id} = $rule;
   
    return $rule;
}

sub resolve_normalized_rule_for_class_and_params {
    my $class = shift;
    my ($unnormalized_rule, @extra) = $class->resolve_for_class_and_params(@_);
    my $normalized_rule = $unnormalized_rule->get_normalized_rule_equivalent();
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
    my $value_id = $class->values_to_value_id(@values);
    my $rule_id = $class->composite_id($template_id,$value_id);
    $class->get($rule_id);
}

our $resolve_depth;
sub resolve_for_class_and_params {
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
    my $subject_class_meta = $subject_class->get_class_object;
    unless ($subject_class_meta) {
        die "No meta for $subject_class?!";
    }    

    my %subject_class_props = map {$_, 1}  ( $subject_class_meta->all_property_type_names, 'subclass_ext');

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
    my $count = @in_params/2;
    my (@keys,@values,@constant_values,$key,$value,$op,@extra,@non_ur_object_refs);
    for (my $n = 0; $n<$count; $n+=1) {
        $key = $in_params[$n*2];
        
        $value = $in_params[$n*2+1];    
        if (substr($key,0,1) eq "-") {
            # these are keys whose values live in the rule template            
            push @keys, $key;
            push @constant_values, $value;
            next;
        }
        
        if (substr($key,0,1)  eq "_") {
            # skip the param
            next;
        } 
        
        my ($property_name,$operator);
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
                if (my $attr = $subject_class_meta->get_property_object(property_name => $property_name)) {
                    die "Property found but not in array of properties?";
                }
                else {
                    push @extra, ($key => $value);
                    next;
                }
            }
        }
        
        if (ref($value) eq "HASH") {
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
        elsif (ref($value) eq "ARRAY") {
            $key .= " []";
            if (blessed($value->[0])) {
                # replace the arrayref
                $value = [ @$value ];
                # transform objects into IDs
                my ($method) = ($key =~ /^(\w+)/);
                if (my $subref = $subject_class->can($method) and $subject_class->isa("UR::Object")) {
                    for (@$value) { $_ =  $subref->($_) };
                }
                # sort
		        no warnings;
                @$value = sort { $a <=> $b or $a cmp $b } @$value;
		        use warnings;
            }
            else {
                no warnings;
                # sort and replace the arrayref
                $value = [
                    sort { $a <=> $b or $a cmp $b } 
                    @$value
                ];         
            }
            
            if (@$value) {
                no warnings;
                # sort and replace the arrayref
                $value = [
                    sort { $a <=> $b or $a cmp $b } 
                    @$value
                ];
                
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
            my $property_type = $subject_class_meta->get_property_object(property_name => $key);
            unless ($property_type) {
                for my $class_name ($subject_class_meta->ordered_inherited_class_names) {
                    my $class_object = $class_name->get_class_object;
                    $property_type = $subject_class_meta->get_property_object(property_name => $key);
                    last if $property_type;
                }
                unless ($property_type) {
                    die "No property type found for $subject_class $key?";
                }
            }
            
            if ($property_type->is_delegated) {
                my $property_meta = $subject_class_meta->get_property_meta_by_name($key);
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
        push @keys, $key;
        push @values, $value;
    }

    my $value_id = UR::BoolExpr->values_to_value_id(@values);
    my $constant_value_id = UR::BoolExpr::Util->values_to_value_id(@constant_values);
    
    my $rule_template_id = $subject_class . '/And/' . join(",",@keys) . "/" . $constant_value_id;
    my $rule_id = join($id_sep,$rule_template_id,$value_id);

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

sub get_normalized_rule_equivalent {
    my $self = shift;
    
    my $rule_template = $self->get_rule_template;
    
    if ($rule_template->{is_normalized}) {
        return $self;
    }
    
    my @unnormalized_values = $self->get_values();
    
    return $rule_template->get_normalized_rule_for_values(@unnormalized_values);
}

sub legacy_params_hash {
    my $self = shift;
        
    # See if we have one already.
    my $params_array = $self->{legacy_params_array};
    return { @$params_array } if $params_array;
    
    # Make one by starting with the one on the rule template
    my $rule_template = $self->get_rule_template;
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

sub create_from_filter_string {
    my ($self, $subject_class_name, $filter_string) = @_;

    my ($property, $op, $value);
    no warnings;
    my @filters = map {
        unless (
            ($property, $op, $value) =
            ($_ =~ /^\s*(\w+)\s*(\@|\=|!=|=|\>|\<|~|\:|\blike\b)\s*['"]?([^'"]*)['"]?\s*$/)
        ) {
            die "Unable to process filter $_\n";
        }
        $op = "like" if $op eq "~";

        [$property, $op, $value]
    } split(/,/, $filter_string);

    use warnings;
    
    return __PACKAGE__->create_from_filters($subject_class_name, @filters);
}

sub create_from_command_line_format_filters {
    __PACKAGE__->warning_message("Deprecated, please use 'create_from_filters'.  API is the same.  Continuing...");
    return create_from_filters(@_);
}

sub create_from_filters {
    my $class = shift;
    
    my $subject_class_name = shift;
    my @filter = @_;

    my @rule_filters;
    
    my @keys;
    my @values;

    for my $fdata (@filter) {
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
            $DB::single = 1;
            $key = $fdata->[0] . ($fdata->[1] and $fdata->[1] ne '='? ' ' . $fdata->[1] : '');
            $value = $fdata->[2];
            $rule_filter = [ @$fdata ];
        }
        
        push @keys, $key;
        push @values, $value;
    } 

    return UR::BoolExpr->create_from_subject_class_name_keys_and_values(
        subject_class_name => $subject_class_name,
        keys => \@keys,
        values=> \@values
    );
}

sub create_from_subject_class_name_keys_and_values {
    my $class = shift;
    
    my %params = @_;
    
    my $subject_class_name = $params{subject_class_name};
    my @values          = @{ $params{values} || [] };
    my @constant_values = @{ $params{constant_values} || [] };
    my @keys            = @{ $params{keys} || [] };

    my $value_id = UR::BoolExpr->values_to_value_id(@values);
    my $constant_value_id = UR::BoolExpr::Util->values_to_value_id(@constant_values);
    
    my $rule_template_id = $subject_class_name . '/And/' . join(",",@keys) . "/" . $constant_value_id;
    my $rule_id = join($id_sep,$rule_template_id,$value_id);

    my $rule = __PACKAGE__->get($rule_id);

    $rule->{values} = \@values;

    #if (@non_ur_object_refs) {
    #    $rule->{non_ur_object_refs} = { @non_ur_object_refs };
    #}
    return $rule;
}

1;


=head1 SYNOPSIS
    
    my $r = GSC::Clone->get_rule_for_params(
        "status" => "active",
        "chromosome" => [2,4,7],
        "clone_name like" => "Foo%",
        "clone_size between" => [100000,200000],
    );
    
    my $o = GSC::Clone->create(
        status => "active", 
        chromosome => 4, 
        clone_name => "FooBar",
        clone_size => 100500
    );    
        
    $r->specifies_value_for_property_name("chromosome") # true
    
    $r->specified_value_for_property_name("chromosome") # 4
        
    $r->evaluate($o); # true
    
    $o->chromosome(11);
    $r->evaluate($o); # false
    
    
=head1 DESCRIPTION

Rule objects are used internally by the UR API to define data sets.  They 
have a 1:1 correspondence within the WHERE clause in an SQL statement.

The entire rule description is the identity of the rule.  They are not
created, just gotten from the infinite set of all possible rules using the
resolve_normalized_rule_for_class_and_params() class method (flyweight 
constructor.)

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
- A rule_template_id. 
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

=head1 PROPERTIES

=over 4

=item

=back

=head1 GENERAL METHODS

=over 4

=item 

=back

=head1 EXAMPLES


my $bool = $x->evaluate($obj);

my $t = GSC::Clone->get_rule_template_for_params(
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

my $t = $r->get_rule_template;

my @results = $t->get_matching_objects($v1,$v2,$v3);
my @results = $r->get_matching_objects();

@r = $r->get_underlying_rules();
for (@r) {
    print $r->evaluate($c1);
}

my $rt = $r->get_rule_template();
my @rt = $rt->get_underlying_rule_templates();

$r = $rt->get_rule_for_values(@v);

=over 4

Report bugs to <software@watson.wustl.edu>.

=back

=head1 SEE ALSO

UR(3), UR::Object(3), UR::Object::Set(3)

=head1 AUTHOR

Scott Smith <ssmith@watson.wustl.edu>,
Ben Oberkfel <boberkfe@watson.wustl.edu>

# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software.  You may distribute under the terms
# of either the GNU General Public License or the Artistic License, as
# specified in the Perl README file.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

# $Header: /var/lib/cvs/perl_modules/App/Object/BoolExpr.pm,v 1.1 2005/11/12 01:19:24 ssmith Exp $

