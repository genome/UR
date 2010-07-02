package UR::Object::Type;

use warnings;
use strict;

use Sys::Hostname;
use Cwd;
use Scalar::Util qw(blessed);
use Sub::Name;

our %meta_classes;
our $bootstrapping = 1;
our @partially_defined_classes;
our $pwd_at_compile_time = cwd();

sub property_metas {
    my $self = $_[0];
    my @a = map { $self->property_meta_for_name($_) } $self->all_property_names();    
    return @a;
}

# Some accessor methods drawn from properties need to be overridden.
# Some times because they need to operate during bootstrapping.  Sometimes
# because the method needs some special behavior like sorting or filtering.
# Sometimes to optimize performance or cache data

# This needs to remain overridden to enforce the restriction on callers
sub data_source {
    my $self = shift;
    #my $ds = $self->__data_source(@_);
    my $ds = $self->data_source_id(@_);
    my $schema = $self->schema_name;
    
    my @caller = caller(1);
    my $caller = $caller[3] || $0;
    unless(
        $caller    eq 'UR::Context::resolve_data_sources_for_class_meta_and_rule'
        or $caller eq 'UR::Context::resolve_data_source_for_object'
        or $caller eq 'UR::Context::_reverse_all_changes'
        or $caller eq 'UR::Object::Type::_complete_class_meta_object_definitions'
        or $caller eq 'UR::Object::Type::generate_support_class_for_extension'        
        or $caller eq 'UR::Object::Index::_build_data_tree'
        or $caller eq 'UR::Object::Index::_add_object'
        or $caller eq 'UR::Object::Index::_remove_object'
        or $caller eq 'UR::Object::changed'
        or $caller eq 'UR::Object::invalid'
        or $caller eq 'UR::Object::Type::resolve_class_description_perl'
        or $caller eq 'UR::Namespace::Command::Update::Classes::_update_class_metadata_objects_to_match_database_metadata_changes'
    ) {
        #Carp::cluck("Attempt to access the data_source property of a class in $caller. "
        #    . "Calls should instead go to the current context:")
    }
    #return $ds;
    return undef unless $ds;
    my $obj = UR::DataSource->get($ds) || $ds->get();
    return $obj;
}

sub ancestry_class_metas {
    #my $rule_template = UR::BoolExpr::Template->resolve(__PACKAGE__,'id');

    # Can't use the speed optimization of getting a template here.  Using the Context to get 
    # objects here causes endless recursion during bootstrapping
    map { __PACKAGE__->get($_) } shift->ancestry_class_names;
    #return map { $UR::Context::current->get_objects_for_class_and_rule(__PACKAGE__, $_) }
    #       map { $rule_template->get_rule_for_values($_) }
    #       shift->ancestry_class_names;

}

sub property_meta_for_name {
    my ($self, $property_name) = @_;
    my $property;

    my $rule_template = UR::BoolExpr::Template->resolve('UR::Object::Property', 'class_name', 'property_name');

    for my $class ($self->class_name, $self->ancestry_class_names) {
        #$property = UR::Object::Property->get(class_name => $class, property_name => $property_name);
        my $rule = $rule_template->get_rule_for_values($class, $property_name);
        $property = $UR::Context::current->get_objects_for_class_and_rule('UR::Object::Property', $rule);
        return $property if $property;
    }
    return;
}

# FIXME This does pretty much exactly the same work as the property's code generated
# by the class initializer, except that it sorts the items before returning
# them.  Without this sorting, relation properties stop working correctly...
# When properties can specify their sort order, try removing this override
sub direct_id_token_metas
{
    my $self = _object(shift);
    my @id_objects =
        sort { $a->position <=> $b->position }
        UR::Object::Property::ID->get( class_name => $self->class_name );
   return @id_objects;
}

# FIXME Same sorting issues apply here, too
sub direct_id_property_metas
{
    my $self = _object(shift);
    my $template = UR::BoolExpr::Template->resolve('UR::Object::Property', 'class_name', 'attribute_name');
    my @id_property_objects =
        #map { UR::Object::Property->get(class_name => $_->class_name, attribute_name => $_->attribute_name) }
        map { $UR::Context::current->get_objects_for_class_and_rule('UR::Object::Property', $_) }
        map { $template->get_rule_for_values($_->class_name, $_->attribute_name) }
        $self->direct_id_token_metas;
    if (@id_property_objects == 0) {
        @id_property_objects = $self->property_meta_for_name("id");
    }
    return @id_property_objects;
}

sub parent_class_names {
    my $self = shift;   
    return @{ $self->{is} };
}

# FIXME Take a look at id_property_names and all_id_property_names.  
# They look extremely similar, but tests start dying if you replace one
# with the other, or remove both and rely on the property's accessor method
sub id_property_names {    
    my $self = _object(shift);
    my @id_by;
    #my $template = UR::BoolExpr::Template->resolve('UR::Object::Type', 'class_name');

    unless ($self->{id_by} and @id_by = @{ $self->{id_by} }) {
        foreach my $parent ( @{ $self->{'is'} } ) {
            my $parent_class = UR::Object::Type->get(class_name => $parent);
            #my $rule = $template->get_rule_for_values($parent);
            #my $parent_class = $UR::Context::current->get_objects_for_class_and_rule('UR::Object::Type', $rule);
            next unless $parent_class;
            @id_by = $parent_class->id_property_names;
            last if @id_by;
        }
    }   
    return @id_by;    
}

sub all_id_property_names {
# return shift->id_property_names(@_); This makes URT/t/99_transaction.t fail
    my $self = shift;
    unless ($self->{_all_id_property_names}) {
        my ($tmp,$last) = ('','');
        $self->{_all_id_property_names} = [
            grep { $tmp = $last; $last = $_; $tmp ne $_ }
            sort 
            map { @{ $_->{id_by} } } 
            map { __PACKAGE__->get($_) }
            ($self->class_name, $self->ancestry_class_names)
        ];
    }
    return @{ $self->{_all_id_property_names} };
}

sub direct_id_column_names
{
    my $self = _object(shift);
    my @id_column_names =
        map { $_->column_name }
        $self->direct_id_property_metas;
    return @id_column_names;
}


sub ancestry_table_names
{
    my $self = _object(shift);
    my @inherited_table_names =
        grep { defined($_) }
        map { $_->table_name }
        $self->ancestry_class_metas;
    return @inherited_table_names;
}

sub all_table_names
{
    my $self = _object(shift);
    my @table_names =
        grep { defined($_) }
        ( $self->table_name, $self->ancestry_table_names );
    return @table_names;
}

sub ancestry_class_names {
    my $self = shift;
    
    if ($self->{_ordered_inherited_class_names}) {
        return @{ $self->{_ordered_inherited_class_names} };
    }
    
    my $ordered_inherited_class_names = $self->{_ordered_inherited_class_names} = [ @{ $self->{is} } ];    
    my @unchecked = @$ordered_inherited_class_names;
    my %seen = ( $self->{class_name} => 1 );
    while (my $ancestor_class_name = shift @unchecked) {
        next if $seen{$ancestor_class_name};
        $seen{$ancestor_class_name} = 1;
        my $class_meta = $ancestor_class_name->__meta__;
        Carp::confess("Can't find meta for $ancestor_class_name!") unless $class_meta;
        next unless $class_meta->{is};
        push @$ordered_inherited_class_names, @{ $class_meta->{is} };
        unshift @unchecked, $_ for reverse @{ $class_meta->{is} };
    }    
    #print "Set for $self->{class_name} to @$ordered_inherited_class_names\n";
    return @$ordered_inherited_class_names;
}

sub all_property_names {
    my $self = shift;
    
    if ($self->{_all_property_names}) {
        return @{ $self->{_all_property_names} };
    }
 
    my %seen = ();   
    my $all_property_names = $self->{_all_property_names} = [];
    for my $class_name ($self->class_name, $self->ancestry_class_names) {
        my $class_meta = UR::Object::Type->get($class_name);
        if (my $has = $class_meta->{has}) {
            push @$all_property_names, 
                grep { 
                    not exists $has->{$_}{id_by}
                }
                grep { $_ ne "id" && !exists $seen{$_} } 
                sort keys %$has;
            foreach (@$all_property_names) {
                $seen{$_} = 1;
            }
        }
    }
    return @$all_property_names;
    
}


########################################################################
# End of overridden property methods
########################################################################

sub _resolve_meta_class_name_for_class_name {
    my $class = shift;
    my $class_name = shift;
    #if ($class_name->isa("UR::Object::Type") or $meta_classes{$class_name} or $class_name =~ '::Type') {
    if ($meta_classes{$class_name} or $class_name =~ '::Type') {
        return "UR::Object::Type"
    }
    else {
        return $class_name . "::Type";
    }    
}

sub _resolve_meta_class_name {
    my $class = shift;
    my ($rule,%extra) = UR::BoolExpr->resolve_normalized($class, @_);
    my %params = $rule->params_list;
    my $class_name = $params{class_name};
    return unless $class_name;
    return $class->_resolve_meta_class_name_for_class_name($class_name);
}


# This method can go away when we have the is_cached meta-property
sub first_sub_classification_method_name {
    my $self = shift;
    
    # This may be one of many things which class meta-data should "inherit" from classes which 
    # its instances inherit from.  This value is set to the value found on the most concrete class
    # in the inheritance tree.

    return $self->{___first_sub_classification_method_name} if exists $self->{___first_sub_classification_method_name};
    
    $self->{___first_sub_classification_method_name} = $self->sub_classification_method_name;
    unless ($self->{___first_sub_classification_method_name}) {
        for my $parent_class ($self->ancestry_class_metas) {
            last if ($self->{___first_sub_classification_method_name} = $parent_class->sub_classification_method_name);
        }
    }
    
    return $self->{___first_sub_classification_method_name};
}


# Another thing that is "inherited" from parent class metas
sub subclassify_by {
    my $self = shift;

    return $self->{'__subclassify_by'} if exists $self->{'__subclassify_by'};

    $self->{'__subclassify_by'} = $self->__subclassify_by;
    unless ($self->{'__subclassify_by'}) {
        for my $parent_class ($self->ancestry_class_metas) {
            last if ($self->{'__subclassify_by'} = $parent_class->__subclassify_by);
        }
    }

    return $self->{'__subclassify_by'};
}

    


sub resolve_composite_id_from_ordered_values {    
    my $self = shift;
    my $resolver = $self->get_composite_id_resolver;
    return $resolver->(@_);
}

sub resolve_ordered_values_from_composite_id {
    my $self = shift;
    my $decomposer = $self->get_composite_id_decomposer;
    return $decomposer->(@_);
}

sub get_composite_id_decomposer {
    my $self = shift;
    my $decomposer;
    unless ($decomposer = $self->{get_composite_id_decomposer}) {
        my @id_property_names = $self->id_property_names;        
        if (@id_property_names == 1) {
            $decomposer = sub { $_[0] };
        }
        else {
            my $separator = $self->_resolve_composite_id_separator;
            $decomposer = sub { 
                if (ref($_[0])) {
                    # ID is an arrayref, or we'll throw an exception.                    
                    my $id = $_[0];
                    my $underlying_id_count = scalar(@$id);
                    
                    # Handle each underlying ID, turning each into an arrayref divided by property value.
                    my @decomposed_ids;
                    for my $underlying_id (@$id) {
                        push @decomposed_ids, [map { $_ eq '' ? undef : $_ } split(/\t/,$underlying_id)];
                    }
            
                    # Count the property values.
                    my $underlying_property_count = scalar(@{$decomposed_ids[0]}) if @decomposed_ids;
                    $underlying_property_count ||= 0;
            
                    # Make a list of property values, but each value will be an
                    # arrayref of a set of values instead of a single value.
                    my @property_values;
                    for (my $n = 0; $n < $underlying_property_count; $n++) {
                        $property_values[$n] = [ map { $_->[$n] } @decomposed_ids ];
                    }
                    return @property_values;                
                }
                else {
                    # Regular scalar ID.
                    no warnings 'uninitialized';  # $_[0] can be undef in some cases...
                    return split($separator,$_[0])  
                }
            };
        }
        Sub::Name::subname('UR::Object::Type::InternalAPI::composite_id_decomposer(closure)',$decomposer);
        $self->{get_composite_id_decomposer} = $decomposer;
    }
    return $decomposer;
}

sub _resolve_composite_id_separator {   
    # TODO: make the class pull this from its parent at creation time
    # and only have it dump it if it differs from its parent
    my $self = shift;
    my $separator = "\t";
    for my $class_meta ($self, $self->ancestry_class_metas) {
        if ($class_meta->composite_id_separator) {
            $separator = $class_meta->composite_id_separator;
            last;
        }
    }
    return $separator; 
}


sub get_composite_id_resolver {
    my $self = shift;    
    my $resolver;
    unless($resolver = $self->{get_composite_id_resolver}) {
        my @id_property_names = $self->id_property_names;        
        if (@id_property_names == 1) {
            $resolver = sub { $_[0] };
        }
        else {
            my $separator = $self->_resolve_composite_id_separator;
            $resolver = sub { 
                if (ref($_[0]) eq 'ARRAY') {                
                    # Determine how big the arrayrefs are.
                    my $underlying_id_count = scalar(@{$_[0]});
                    
                    # We presume that, if one value is an arrayref, the others are also,
                    # and are of equal length.
                    my @id;
                    for (my $id_num = 0; $id_num < $underlying_id_count; $id_num++) {
                        # One value per id_property on the class.
                        # Each value is an arrayref in this case.
                        for my $value (@_) {
                            no warnings 'uninitialized';  # Some values in the list might be undef
                            $id[$id_num] .= $separator if $id[$id_num];
                            $id[$id_num] .= $value->[$id_num];
                        }
                    }
                    return \@id;           
                }
                else {
                    no warnings 'uninitialized';  # Some values in the list might be undef
                    return join($separator,@_) 
                }
            };
        }
        Sub::Name::subname('UR::Object::Type::InternalAPI::composite_id_resolver(closure)',$resolver);
        $self->{get_composite_id_resolver} = $resolver;
    }    
    return $resolver;
}

    # UNUSED, BUT BETTER FOR MULTI-COLUMN FK
    sub composite_id_list_scalar_mix {
        # This is like the above, but handles the case of arrayrefs
        # mixing with scalar values in a multi-property id.

        my ($self, @values) = @_;

        my @id_sets;
        for my $value (@values) {
            if (@id_sets == 0) {
                if (not ref $value) {
                    @id_sets = ($value);
                }
                else {
                    @id_sets = @$value;
                }
            }
            else {
                if (not ref $value) {
                    for my $id_set (@id_sets) {
                        $id_set .= "\t" . $value;
                    }
                }
                else {
                    for my $new_id (@$value) {
                        for my $id_set (@id_sets) {
                            $id_set .= "\t" . $value;
                        }
                    }
                }
            }
        }

        if (@id_sets == 1) {
            return $id_sets[0];
        }
        else {
            return \@id_sets;
        }
    }


# Return a closure that sort can use to sort objects by all their ID properties
# This should be the same order that an SQL query with 'order by ...' would return them
sub id_property_sorter {
    my $self = shift;
    return $self->{'_id_property_sorter'} ||= $self->sorter(); 
}

#TODO: make this take +/- indications of ascending/descending
#TODO: make it into a closure for speed
#TODO: there are possibilities of it sorting different than a DB on mixed numbers and alpha data
sub sorter {
    my ($self,@properties) = @_;
    push @properties, $self->id_property_names;
    my $key = join(",",@properties);
    my $sorter = $self->{_sorter}{$key} ||= sub($$) {
        no warnings;   # don't print a warning about non-numeric comparison with <=> on the next line
        for my $property (@properties) {
            my $cmp = ($_[0]->$property <=> $_[1]->$property || $_[0]->$property cmp $_[1]->$property);
            return $cmp if $cmp;
        }
        return 0;
    };
    Sub::Name::subname("UR::Object::Type::sorter__class_".$self->class_name, $sorter);
    return $sorter;
}

sub is_meta {
    my $self = shift;
    my $class_name = $self->class_name;
    return grep { $_ ne 'UR::Object' and $class_name->isa($_) } keys %meta_classes;
}

sub is_meta_meta {
    my $self = shift;
    my $class_name = $self->class_name;
    return 1 if $meta_classes{$class_name};
    return;
}

# Things that can't safely be removed from the object cache.
our %uncachable_types = ( ( map { $_ => 0 } keys %UR::Object::Type::meta_classes),   # meta-classes are locked in the cache...
                          'UR::Object' => 1,        # .. except for UR::Object
                          'UR::Object::Ghost' => 0,
                          'UR::DataSource' => 0,
                          'UR::Context' => 0,
                          'UR::Object::Index' => 0,
                        );
sub is_uncachable {
    my $self = shift;

    my $class_name = $self->class_name;
    unless (exists $uncachable_types{$class_name}) {
        foreach my $type ( keys %uncachable_types ) {
            if ($class_name->isa($type)) {
                $uncachable_types{$class_name} = $uncachable_types{$type};
                last;
            }
        }
        unless (exists $uncachable_types{$class_name}) {
            die "Couldn't determine is_uncachable() for $class_name";
        }
    }
    return $uncachable_types{$class_name};
}

# Support the autogeneration of unique IDs for objects which require them.
# We use the host, time, and pid.
our $autogenerate_id_base = join(" ",hostname(), $$, time);
our $autogenerate_id_iter = 10000;
sub autogenerate_new_object_id {
    my $self = shift;
    my $rule = shift;

    my ($data_source) = $UR::Context::current->resolve_data_sources_for_class_meta_and_rule($self);
    if ($data_source) {
        return $data_source->autogenerate_new_object_id_for_class_name_and_rule(
            $self->class_name,
            $rule
        )
    }
    else {
        my @id_property_names = $self->id_property_names;
        if (@id_property_names > 1) {
            # we really could (as you can see below), but it seems like if you 
            # asked to do it, it _has_ to be a mistake.  If there's a legitimate
            # reason, this check should be removed
            $self->error_message("Can't autogenerate ID property values for multiple ID property class " . $self->class_name);
            return;
        }
        return $autogenerate_id_base . " " . (++$autogenerate_id_iter);

        #my @id_parts;
        #my $supplied_params = $rule->legacy_params_hash;
        #foreach my $prop ( $self->id_property_names ) {
        #    if (exists $supplied_params->{$prop}) {
        #        push(@id_parts,$supplied_params->{$prop});
        #    } else {
        #        push(@id_parts, $autogenerate_id_base . " " . (++$autogenerate_id_iter));
        #    }
        #}
        #return join("\t",@id_parts);
    }
}

# from ::Object->generate_support_class
our %support_class_suffixes = map { $_ => 1 } qw/Set View Viewer Ghost Iterator Value/;
sub generate_support_class_for_extension {
    my $self = shift;
    my $extension_for_support_class = shift;
    my $subject_class_name = $self->class_name;

    unless ($subject_class_name) {
        Carp::confess("No subject class name for $self?"); 
    }

    return unless defined $extension_for_support_class;

    if ($subject_class_name eq "UR::Object") {
        # Carp::cluck("can't generate $extension_for_support_class for UR::Object!\n");
        # NOTE: we hit this a bunch of times when "getting" meta-data objects during boostrap.
        return;
    }

    #print "generating support class $extension_for_support_class for $subject_class_name\n";

    unless ($support_class_suffixes{$extension_for_support_class})
    {
        #$self->debug_message("Cannot generate a class with extension $extension_for_support_class.");
        return;
    }

    my $subject_class_obj = UR::Object::Type->get(class_name => $subject_class_name);
    unless ($subject_class_obj)  {
        $self->debug_message("Cannot autogenerate $extension_for_support_class because $subject_class_name does not exist.");
        return;
    }

    my $new_class_name = $subject_class_name . "::" . $extension_for_support_class;
    my $class_obj;
    if ($class_obj = UR::Object::Type->is_loaded($new_class_name)) {
        # getting the subject class autogenerated the support class automatically
        # shortcut out
        return $class_obj;
    }

    no strict 'refs';
    my @subject_parent_class_names = @{ $subject_class_name . "::ISA" };
    my @parent_class_names =
        grep { UR::Object::Type->get(class_name => $_) }
        map { $_ . "::" . $extension_for_support_class }
        grep { $_->isa("UR::Object") }
        grep { $_ !~ /^UR::/  or $extension_for_support_class eq "Ghost" }
        @subject_parent_class_names;
    use strict 'refs';

    unless (@parent_class_names) {
        if (UR::Object::Type->get(class_name => ("UR::Object::" . $extension_for_support_class))) {
            @parent_class_names = "UR::Object::" . $extension_for_support_class;
        }
    }

    unless (@parent_class_names) {
        #print Carp::longmess();
        #$self->error_message("Cannot autogenerate $extension_for_support_class for $subject_class_name because parent classes (@subject_parent_class_names) do not have classes with that extension.");
        return;
    }
    
    my @id_property_names = $subject_class_obj->id_property_names;
    my %id_property_names = map { $_ => 1 } @id_property_names;
    
    if ($extension_for_support_class eq 'Ghost') {
        my $subject_class_metaobj = UR::Object::Type->get($self->meta_class_name);  # Class object for the subject_class
        #my %class_params = map { $_ => $subject_class_obj->$_ } $subject_class_obj->__meta__->all_property_names;
        my %class_params = map { $_ => $subject_class_obj->$_ }
                           grep { my $p = $subject_class_metaobj->property_meta_for_name($_);
                                  unless($p) { die "can't property_meta_for_name for $_"; }
                                  ! $p->is_delegated and ! $p->is_calculated }
                           $subject_class_obj->__meta__->all_property_names;
        delete $class_params{generated};
        delete $class_params{meta_class_name};
        delete $class_params{subclassify_by};
        delete $class_params{sub_classification_meta_class_name};
        delete $class_params{id_sequence_generator_name};
        delete $class_params{id};
        delete $class_params{is};

        my $attributes_have = UR::Util::deep_copy($subject_class_obj->{attributes_have});
        my $class_props = UR::Util::deep_copy($subject_class_obj->{has});    
        for (values %$class_props) {
            delete $_->{class_name};
            delete $_->{type_name};
            delete $_->{property_name};
            $_->{is_optional} = !$id_property_names{$_};
        }
        
        %class_params = (
                %class_params,
                class_name => $new_class_name,
                is => \@parent_class_names, 
                is_abstract => 0,
                type_name => $subject_class_obj->type_name . " ghost",
                has => [%$class_props],
                attributes_have => $attributes_have,
                id_properties => \@id_property_names,
        );
        #print "D: $new_class_name" . Dumper(\%class_params);
        $class_obj = UR::Object::Type->define(%class_params);
    }
    #elsif ($extension_for_support_class =~ /Edit/) {
    #    $class_obj = UR::Object::Type->define(
    #        class_name => $subject_class_name . "::" . $extension_for_support_class,
    #        is => \@parent_class_names,
    #        has => [ $subject_class_obj->all_property_names ],
    #        id_by => [ $subject_class_obj->id_property_names ]
    #    );
    #}
    else {
        $class_obj = UR::Object::Type->define(
            class_name => $subject_class_name . "::" . $extension_for_support_class,
            is => \@parent_class_names,
        );
    }
    return $class_obj;
}

sub has_table {
    my $self = shift;
    if ($bootstrapping) {
        return 0;
    }
    return 1 if $self->table_name;
    # FIXME - shouldn't this call inheritance() instead of parent_classes()?
    my @parent_classes = $self->parent_classes;
    for my $class_name (@parent_classes) {
        next if $class_name eq "UR::Object";
        my $class_obj = UR::Object::Type->get(class_name => $class_name);
        if ($class_obj->table_name) {
            return 1;
        }
    }
    return;
}

sub most_specific_subclass_with_table {
    my $self = shift;

    return $self->class_name if $self->table_name;

    foreach my $class_name ( $self->class_name->inheritance ) {
        my $class_obj = UR::Object::Type->get(class_name => $class_name);
        return $class_name if ($class_obj && $class_obj->table_name);
    }
    return;
}

sub most_general_subclass_with_table {
    my $self = shift;

    my @subclass_list = reverse ( $self->class_name, $self->class_name->inheritance );
    foreach my $class_name ( $self->inheritance ) {
        my $class_obj = UR::Object::Type->get(class_name => $class_name);
        return $class_name if ($class_obj && $class_obj->table_name);
    }
    return;
}

    

sub _load {
    my $class = shift;
    my $rule = shift;

    my $params = $rule->legacy_params_hash;

    # While core entity classes are actually loaded,
    # support classes dynamically generate for them as needed.
    # Examples are Acme::Employee::View::emp_id, and Acme::Equipment::Ghost

    # Try to parse the class name.
    my $class_name = $params->{class_name};
    #my $class_name = $params->{'meta_class_name'} || $params->{class_name};

    # See if the class autogenerates from another class.
    # i.e.: Acme::Foo::Bar might be generated by Acme::Foo
    unless ($class_name) {
        my $namespace = $params->{namespace};
        if (my $data_source = $params->{data_source_id}) {
            $namespace = $data_source->get_namespace;
        }
        if ($namespace) {
            # FIXME This chunk seems to be getting called each time there's a new table/class
            #Carp::cluck("Getting all classes for namespace $namespace from the filesystem...");
            my @classes = $namespace->get_material_classes;
            return $class->is_loaded($params);
        }
        my @params = %$params;
        Carp::confess("Non-class_name used to find a class object: @params");
    }

    # Besides the common case of asking for a class by its name, the next most
    # common thing is asking for multiple classes by their names.  Rather than doing the
    # hard work of doing it "right" right here, just recursively call myself with each
    # item in that list
    if (ref $class_name eq 'ARRAY') {
        # FIXME is there a more efficient way to add/remove class_name from the rule?
        my $rule_without_class_name = $rule->remove_filter('class_name');
        $rule_without_class_name = $rule_without_class_name->remove_filter('id');  # id is a synonym for class_name
        my @objs = map { $class->_load($rule_without_class_name->add_filter(class_name => $_)) } @$class_name;
        return $class->context_return(@objs);
    }
        
    # If the class is loaded, we're done.
    # This is an un-documented unique constraint right now.
    my $class_obj = $class->is_loaded(class_name => $class_name);
    return $class_obj if $class_obj;

    # Handle deleted classes.
    # This is written in non-oo notation for bootstrapping.
    no warnings;
    if (
        $class_name ne "UR::Object::Type::Ghost"
        and
        UR::Object::Type::Ghost->can("class")
        and
        $UR::Context::current->get_objects_for_class_and_rule("UR::Object::Type::Ghost",$rule,0)
    ) {
        return;
    }

    # Check the filesystem.  The file may create its metadata object.
    if ($class->class->use_module_with_namespace_constraints($class_name)) {
        # If the above module was loaded, and is an UR::Object,
        # this will find the object.  If not, it will return nothing.
        $class_obj = $UR::Context::current->get_objects_for_class_and_rule($class,$rule,0);
        return $class_obj if $class_obj;
    }

    # print "dynamically 'loading' special $class_name\n";

    # Parse the specified class name to check for a suffix.
    my ($prefix, $base, $suffix) = ($class_name =~ /^([^\:]+)::(.*)::([^:]+)/);

    my @parts;
    ($prefix, @parts) = split(/::/,$class_name);

    for (my $suffix_pos = $#parts; $suffix_pos >= 0; $suffix_pos--)
    {
        $class_obj = $UR::Context::current->get_objects_for_class_and_rule($class,$rule,0);
        if ($class_obj) {
            # the class was somehow generated while we were checking other classes for it and failing.
            # this can happen b/c some class with a name which is a subset of the one we're looking
            # for might "use" the one we want.
            return $class_obj if $class_obj;
        } 

        my $base   = join("::", @parts[0 .. $suffix_pos-1]);
        my $suffix = join("::", @parts[$suffix_pos..$#parts]);

        # See if a class exists for the same name w/o the suffix.
        # This may cause this function to be called recursively for
        # classes like Acme::Equipment::Set::View::upc_code,
        # which would fire recursively for three extensions of
        # Acme::Equipment.
        my $full_base_class_name = $prefix . ($base ? "::" . $base : "");
        my $base_class_obj = UR::Object::Type->get(class_name => $full_base_class_name);

        if ($base_class_obj)
        {
            # If so, that class may be able to generate a support
            # class.
            $class_obj = $full_base_class_name->__extend_namespace__($suffix);
            if ($class_obj)
            {
                # Autogeneration worked.
                # We still defer to is_loaded, since other parameters
                # may prevent the newly "loaded" class from being
                # returned.                
                return $UR::Context::current->get_objects_for_class_and_rule($class,$rule,0)
            }
        }
    }

    # Try the super class next, which will check the database.
    # This will be moved below the use_packages when generate is fixed,
    # and then removed entirely when the clases are all on the filesystem.
    #if (my @classes = $class->SUPER::load(@_))
    #{
    #    return @classes if wantarray;
    #    die "Multiple matches for $class @_!" if @classes > 1;
    #    return $classes[0];
    #}

    # If we fall-through to this point, no class was found and no module.
    return;
}


sub use_module_with_namespace_constraints {
    use strict;
    use warnings;

    my $self = shift;
    my $target_class = shift;

    # If you do "use Acme; $o = Acme::Rocket->new();", and Perl finds Acme.pm
    # at "/foo/bar/Acme.pm", Acme::Rocket must be under /foo/bar/Acme/
    # in order to be dynamically loaded.

    my @words = split("::",$target_class);

    my $namespace_name = shift @words;
    my $namespace_expected_module = $namespace_name . ".pm";

    my $path;
# Looks like this isn't needed anymore?  
#    if ($namespace_name eq "App" or $namespace_name eq "UR") {
#        #$module_name = $namespace_name . ".pm";
#        #$path = $INC{$module_name};
#        #unless ($path) {
#        #    Carp::confess("No \%INC entry for $module_name?");
#        #}
#        #$path =~ s/\/[^\/]+\.pm//;
#
#        # use this directly to avoid boostrapping problems.
#        $path = undef;
#    }
#    elsif ($path = $INC{$namespace_expected_module}) {

    if ($path = $INC{$namespace_expected_module}) {
        #print "got mod $namespace_expected_module at $path for $target_class\n";
        $path =~ s/\/*$namespace_expected_module//g;
    }
    else {
        my $namespace_obj =  UR::Object::Type->is_loaded(class_name => $namespace_name);
        unless ($namespace_obj) {
            #print("Skipping autoload of module name: $target_class since namespace $namespace_name is not loaded.\n");
            return;
        }

        eval { $path = $namespace_obj->module_directory };
        if ($@) {
            # non-module class
            # don't auto-use, but don't make a lot of noise about it either
            return;
        }
        unless ($path) {
            #Carp::cluck("No module_directory found for namespace $namespace_name."
            #    . "  Cannot dynamically load $target_class.");
            return;
        }
    }

    $self->_use_safe($target_class,$path);
    my $meta = UR::Object::Type->is_loaded(class_name => $target_class);
    if ($meta) {
        return $meta;
    }
    else {
        return;
    }
}

sub _use_safe {
    use strict;
    use warnings;

    my ($self, $target_class, $expected_directory) = @_;

    # TODO: use some smart module to determine whether the path is
    # relative on the current system.
    if (defined($expected_directory) and $expected_directory !~ /^[\/\\]/) {
        $expected_directory = $pwd_at_compile_time . "/" . $expected_directory;
    }

    my $class_path = $target_class . ".pm";
    $class_path =~ s/\:\:/\//g;

    my @INC_COPY = @INC;
    if ($expected_directory) {
        unshift @INC, $expected_directory;
    }
    my $found = "";
    for my $dir (@INC) {
        if ($dir and (-e $dir . "/" . $class_path)) {
            $found = $dir;
            last;
        }
    }

    if (!$found) {
        # not found
        @INC = @INC_COPY;
        return;
    }

    if ($expected_directory and $expected_directory ne $found) {
        # not found in the specified location
        @INC = @INC_COPY;
        return;
    }

    do {
        local $SIG{__DIE__};
        local $SIG{__WARN__};
        eval "use $target_class";
    };

    # FIXME - if the use above failed because of a compilation error in the module we're trying to
    # load, then the error message below just tells the user that "Compilation failed in require"
    # and isn't propogating the error message about what caused the compile to fail
    if ($@) {
        #local $SIG{__DIE__};

        @INC = @INC_COPY;
        die ("ERROR DYNAMICALLY LOADING CLASS $target_class\n$@");
    }

    for (0..$#INC) {
        if ($INC[$_] eq $expected_directory) {
            splice @INC, $_, 1;
            last;
        }
    }

    return 1;
}


# Create the table behind this class in the specified database.
# Currently, it creates sql valid for SQLite for support of loading
# up a testing DB.  Maybe this should be moved somewhere under the
# DataSource objects
sub mk_table {
    my($self,$dbh) = @_;
    return 1 unless $self->has_table;

    $dbh ||= $self->dbh;

    my $table_name = $self->table_name();
    # we only care about properties backed up by a real column
    my @props = grep { $_->column_name } $self->direct_property_metas();

    my $sql = "create table $table_name (";

    my @cols;
    foreach my $prop ( @props ) {
        my $col = $prop->column_name;
        my $type = $prop->data_type;
        my $len = $prop->data_length;
        my $nullable = $prop->nullable;

        my $string = "$col" . " " . $type;
        $string .= " NOT NULL" unless $nullable;
        push @cols, $string;
    }
    $sql .= join(',',@cols);

    my @id_cols = $self->direct_id_column_names();
    $sql .= ", PRIMARY KEY (" . join(',',@id_cols) . ")" if (@id_cols);

    # Should we also check for the unique properties?

    $sql .= ")";

    unless ($dbh->do($sql) ) {
        $self->error_message("Can't create table $table_name: ".$DBI::errstr."\nSQL: $sql");
        return undef;
    }

    1;
}

# sub _object
# This is used to make sure that methods are called
# as object methods and not class methods.
# The typical case that's important is when something
# like UR::Object::Type->method(...) is called.
# If an object is expected in a method and it gets
# a class instead, well, unpredictable things can
# happen.
#
# For many methods on UR::Objects, the implementation
# is in UR::Object.  However, some of those methods
# have the same name as methods in here (purposefully),
# and those UR::Object methods often get the
# UR::Object::Type object and call the same method,
# which ends up in this file.  The problem is when
# those methods are called on UR::Object::Type
# itself it come directly here, without getting
# the UR::Object::Type object for UR::Object::Type
# (confused yet?).  So to fix this, we use _object to
# make sure we have an object and not a class.
#
# Basically, we make sure we're working with a class
# object and not a class name.
#

sub _object
{
    return ref($_[0]) ? $_[0] : $_[0]->__meta__;
}


# FIXME These *type_names methods should be replaced via the new metadata API.
# also of note, type_names are going away, so maybe don't bother
# What exactly are these used for?
sub Xderived_type_names
{
    #Carp::confess();
    my $self = shift;
    my $class_name = $self->class_name;
    my @sub_class_links = UR::Object::Inheritance->get(parent_class_name => $class_name);
    my @sub_type_names = map { $_->type_name } @sub_class_links;
    return @sub_type_names;
}

sub Xall_derived_type_names
{
    #Carp::confess();
    my $self = shift;
    my @sub_type_names = $self->derived_type_names;
    my @all_sub_type_names;
    while (@sub_type_names) {
        push @all_sub_type_names, @sub_type_names;
        @sub_type_names =
            map { $_->type_name }
            UR::Object::Inheritance->get(parent_type_name => \@sub_type_names);
    }
    return @all_sub_type_names;
}

# new version gets everything, including "id" itself and object ref properties
sub all_property_type_names {
    my $self = shift;
    
    if ($self->{_all_property_type_names}) {
        return @{ $self->{_all_property_type_names} };
    }
    
    #my $rule_template = UR::BoolExpr::Template->resolve('UR::Object::Type', 'id');

    my $all_property_type_names = $self->{_all_property_type_names} = [];
    for my $class_name ($self->class_name, $self->ancestry_class_names) {
        my $class_meta = UR::Object::Type->get($class_name);
        #my $rule = $rule_template->get_rule_for_values($class_name);
        #my $class_meta = $UR::Context::current->get_objects_for_class_and_rule('UR::Object::Type',$rule);
        if (my $has = $class_meta->{has}) {            
            push @$all_property_type_names, sort keys %$has;
        }
    }
    return @$all_property_type_names;
}

sub table_for_property
{
    my $self = _object(shift);
    die 'must pass a property_name to table_for_property' unless @_;
    my $property_name = shift;
    for my $class_object ( $self, $self->ancestry_class_metas )
    {
        my $property_object = UR::Object::Property->get( class_name => $class_object->class_name, property_name => $property_name );
        if ( $property_object )
        {
            return unless $property_object->column_name;
            return $class_object->table_name;
        }
    }

    return;
}

sub column_for_property
{
    my $self = _object(shift);
    die 'must pass a property_name to column_for_property' unless @_;
    my $property_name = shift;
    my $class_name = $self->class_name;
    my $column_name;
    do { 
    no strict 'refs';
     $column_name = ${$class_name . "::column_for_property"}{ $property_name };
    };
    return $column_name if $column_name;
    for my $class_object ( $self->ancestry_class_metas )
    {
        my $cn = $class_object->class_name;
        do { 
	no strict 'refs';
        $column_name = ${$cn . "::column_for_property"}{ $property_name };
	};
        return $column_name if $column_name;
    }
    $class_name = $self->class_name;
    #die "$property_name is not a property of $class_name";
    return;
}

sub property_for_column
{
    my $self = _object(shift);
    die 'must pass a column_name to property_for_column' unless @_;
    my $column_name = shift;
    my $class_name = $self->class_name;
    my $property_name = ${$class_name . "::property_for_column"}{ $column_name };
    return $property_name if $property_name;
    for my $class_object ( $self->ancestry_class_metas )
    {
        my $cn = $class_object->class_name;
        $property_name = ${$cn . "::property_for_column"}{ $column_name };
        return $property_name if $property_name;
    }
    $class_name = $self->class_name;
    #die "$column_name is not a column for $class_name";
    return;
}

# ::Object unique_properties
# FIXME The new API doesn't have a replacement for this 
# FIXME - and it doesn't seem to be called by anything....
# This returns a list of lists.  Each inner list is the properties/columns
# involved in the constraint
sub unique_property_sets
{
    my $self = shift; 
    if ($self->{_unique_property_sets}) {
        return @{ $self->{_unique_property_sets} };
    }

    my $unique_property_sets = $self->{_unique_property_sets} = [];

    for my $class_name ($self->class_name, $self->ancestry_class_names) {
        my $class_meta = UR::Object::Type->get($class_name);
        if ($class_meta->{constraints}) {            
            for my $spec (@{ $class_meta->{constraints} }) {
                push @$unique_property_sets, [ @{ $spec->{properties} } ] 
            }
        }
    }
    return @$unique_property_sets;

    my %all;
    #for my $unique_object ( $self->get_unique_objects )  # old API
    for my $unique_object ( $self->unique_metas )         # new API
    {
        my $property_object = UR::Object::Property->get(class_name => $unique_object->class_name, attribute_name => $unique_object->attribute_name);
        my $unique_group = $unique_object->unique_group;
        $all{$unique_group} ||= [];
        push @{ $all{$unique_group} }, $property_object->property_name;
    }

    for my $group (keys %all)
    {
        my $property_list = $all{$group};

        if (@$property_list == 1)
        {
            $all{$group} = $property_list->[0]
        }
    }

    return values(%all);
}

# Return the constraint information as a hashref
# keys are the SQL constraint name, values are a listref of property/column names involved
sub unique_property_set_hashref {
    my $self = shift;

    if ($self->{_unique_property_set_hashref}) {
        return $self->{_unique_property_set_hashref};
    }

    my $unique_property_set_hashref = $self->{_unique_property_set_hashref} = {};
   
    for my $class_name ($self->class_name, $self->ancestry_class_names) {
        my $class_meta = UR::Object::Type->get($class_name);
        if ($class_meta->{'constraints'}) {
            for my $spec (@{ $class_meta->{'constraints'} }) {
                my $unique_group = $spec->{'sql'};
                next if ($unique_property_set_hashref->{$unique_group});  # child classes override parents
                $unique_property_set_hashref->{$unique_group} = [ @{$spec->{properties}} ];
            }
        }
    }

    return $unique_property_set_hashref;
}


# Used by the class meta meta data constructors to make changes in the 
# raw data stored in the class object's hash.  These should really
# only matter while running ur update

# Args are:
# 1) An UR::Object::Property object with attribute_name, class_name, id, property_name, type_name
# 2) The method called: _create_object, load, 
# 3) An id?
sub _property_change_callback {
    my $property_obj = shift;
    my $method = shift;

    return if ($method eq 'load' || $method eq 'unload' || $method eq '_create_object' || $method eq '_delete_object');

    my $class_obj = UR::Object::Type->get(class_name => $property_obj->class_name);
    my $property_name = $property_obj->property_name;

    if ($method eq 'create') {
        unless ($class_obj->{'has'}->{$property_name}) {
            my @attr = qw( class_name attribute_name data_length data_type is_delegated is_optional property_name type_name );

            my %new_property;
            foreach my $attr_name (@attr ) {
                $new_property{$attr_name} = $property_obj->$attr_name();
            }
            $class_obj->{'has'}->{$property_name} = \%new_property;
        }

    } elsif ($method eq 'delete') {
        delete $class_obj->{'has'}->{$property_name};

    } elsif (exists $class_obj->{'has'}->{$property_name}->{$method}) {
        my $old_val = shift;
        my $new_val = shift;
        $class_obj->{'has'}->{$property_name}->{$method} = $new_val;
    } #elsif ($method ne 'is_optional') {
      #  $DB::single=1;
      #  1;
      #
    #}
    
}

# A streamlined version of the method just below that dosen't check that the
# data in both places is the same before a delete operation.  What was happening
# was that an ID property got deleted and the position checks out ok, but then
# a second ID property gets deleted and now the position dosen't match because we
# aren't able to update the object's position property 'cause it's an ID property
# and can't be changed.  
#
# The short story is that we've lowered the bar for making sure it's safe to delete info
sub _id_property_change_callback {
    my $property_obj = shift;
    my $method = shift;

    return if ($method eq 'load' || $method eq 'unload' || $method eq '_create_object' || $method eq '_delete_object');

    my $class = UR::Object::Type->get(class_name => $property_obj->class_name);
    
    if ($method eq 'create') {
        # Position is 1-based, and the list embedded in the class object is 0-based
        my $pos = $property_obj->position;
        if ($pos > 0) {
            $pos--;
        } else {
            $pos = 0;
        }
        if ($pos <= @{$class->{'id_by'}}) {
            splice(@{$class->{'id_by'}}, $pos, 0, $property_obj->property_name);
        } else {
            # $pos is past the end... probably an id property was deleted and another added
            push @{$class->{'id_by'}}, $property_obj->property_name;
        }
    } elsif ($method eq 'delete') {
        my $property_name = $property_obj->property_name;
        for (my $i = 0; $i < @{$class->{'id_by'}}; $i++) {
            if ($class->{'id_by'}->[$i] eq $property_name) {
                splice(@{$class->{'id_by'}}, $i, 1);
                return;
            }
        }
        $DB::single = 1;
        Carp::confess("Internal data consistancy problem: could not find property named $property_name in id_by list for class meta " . $class->class_name);

    } else {
        # Shouldn't get here since ID properties can't be changed, right?
        $DB::single = 1;
        Carp::confess("Shouldn't be here as ID properties can't change");
        1;
    }
}


sub _unique_property_change_callback {
    my $unique_obj = shift;
    my $method = shift;

    return if ($method eq 'load' || $method eq 'unload' || $method eq '_create_object' || $method eq '_delete_object');

    my $class = UR::Object::Type->get(class_name => $unique_obj->class_name);
    my $property_name = $unique_obj->property_name;

    # The fact that this callback is running means we need to invalidate our caches about
    # unique property data
    delete $class->{'_unique_property_sets'};
    delete $class->{'_unique_property_set_hashref'};

    if ($method eq 'create') {
        my $unique_properties = $class->unique_property_set_hashref();
        my $unique_group = $unique_obj->unique_group;
        unless ( exists $unique_properties->{$unique_group} and grep { $_ eq $property_name } @{$unique_properties->{$unique_group}} ) {
            # Should this constraint be part of an already existing group?
            foreach my $constraint ( @{$class->{'constraints'}} ) {
                if ($constraint->{'sql'} eq $unique_group) {
                    push(@{$constraint->{'properties'}}, $property_name);
                    return;
                }
            }
            # Didn't find an already existing constraint group, make a new one
            push(@{$class->{'constraints'}}, { sql => $unique_group, properties => [ $property_name ] });
        }
    } elsif ($method eq 'delete') {
        my $unique_group = $unique_obj->unique_group;
        for (my $constraint_idx = 0; $constraint_idx < @{$class->{'constraints'}}; $constraint_idx++) {
            next unless ($class->{'constraints'}->[$constraint_idx]->{'sql'} eq $unique_group);
            for (my $property_idx = 0; $property_idx < @{$class->{'constraints'}->[$constraint_idx]->{'properties'}}; $property_idx++) {
                if ($class->{'constraints'}->[$constraint_idx]->{'properties'}->[$property_idx] eq $property_name) {
                    splice(@{$class->{'constraints'}->[$constraint_idx]->{'properties'}}, $property_idx, 1);
                    if (scalar(@{$class->{'constraints'}->[$constraint_idx]->{'properties'}} == 0)) {
                        # No properties left in this group.  Get rid of the whole thing.
                        splice(@{$class->{'constraints'}}, $constraint_idx,1);
                    }
                    last;
                }
            } # end for property_idx
        } # end for constraint_idx
    } else {
        1;
    }
 
}

# Args here are:  
# 1) an UR::Object::Inheritance object with class_name, id, parent_class_name, type_name, parent_type_name
# 2) method called to fire this off:  _create_object, load, 
# 3) Some kind of id property's value?
sub _inheritance_change_callback {
    my $inh_obj = shift;
    my $method = shift;

    return if ($method eq 'load' || $method eq 'unload' || $method eq '_create_object' || $method eq '_delete_object');

    my $class = UR::Object::Type->get(class_name => $inh_obj->class_name);
    # The inheritance_priority is 1-based, while the list in the class object is 0-based,
    # and newly created inheritance objects might not have a priority defined yet
    my $prio = $inh_obj->inheritance_priority();
    if ($prio > 0) {
        $prio--;
    } else {
        $prio = 0;
    }

    if ($method eq 'create' or
        ($method eq 'delete' and $class->{'is'}->[$prio] eq $inh_obj->parent_class_name)) {

        if ($method eq 'create') {
            # we perform this check because class ->create() will have made an "is" values
            # ahead of time, and in such a case there will be nothing to do...
            unless ($class->{is}[0] eq $inh_obj->parent_class_name) {                
                splice(@{$class->{'is'}}, $prio, 0, $inh_obj->parent_class_name);
            }
            $prio++;
        } else {
            splice(@{$class->{'is'}}, $prio, 1);
        }

        # Renumber the remaining inheritances
        for (my $i = $prio; $i < @{$class->{'is'}}; $i++) {
            my $parent_class_name = $class->{'is'}->[$i];
            my $obj = UR::Object::Inheritance->is_loaded(class_name => $class->class_name,
                                                          parent_class_name => $parent_class_name);
            next unless $obj;  # not loaded yet
            $obj->inheritance_priority($i);
        }
    } elsif ($method eq 'inheritance_priority') {
        $DB::single=1;
        1;
    }
}


#
# BOOTSTRAP CODE
#

sub get_with_special_parameters
{
    my $class = shift;
    my $rule = shift;
    my %extra = @_;
    if (my $namespace = delete $extra{'namespace'}) {
        unless (keys %extra) {
            my @c = $namespace->get_material_classes();
            @c = grep { $_->namespace eq $namespace } $class->is_loaded($rule->params_list);
            return $class->context_return(@c);
        }
    }
    return $class->SUPER::get_with_special_parameters($rule,@_);
}

sub __signal_change__ {
    my $self = shift;
    my @rv = $self->SUPER::__signal_change__(@_);
    if ($_[0] eq "delete") {
        my $class_name = $self->{class_name};
        $self->ungenerate();
    }
    return @rv;
}


sub generated {
    my $self = shift;
    if (@_) {
        $self->{'generated'} = shift;
    }
    return $self->{'generated'};
}

sub ungenerate {
    my $self = shift;
    my $class_name = $self->class_name;
    #print "ungenerating $class_name stored in meta " . ref($self) . "\n";
    #print "\t" . Carp::longmess();    
    delete $UR::Object::_init_subclass->{$class_name};
    delete $UR::Object::Type::_inform_all_parent_classes_of_newly_loaded_subclass{$class_name};    
    do {
        no strict;
        no warnings;
        my @symbols_which_are_not_subordinate_namespaces =
            grep { substr($_,-2) ne '::' }
            keys %{ $class_name . "::" };
        my $hr = \%{ $class_name . "::" };
        delete @$hr{@symbols_which_are_not_subordinate_namespaces};        
    };
    my $module_name = $class_name;
    $module_name =~ s/::/\//g;
    $module_name .= ".pm";
    delete $INC{$module_name};    
    $self->{'generated'} = 0;
}



# Experimental unloading of classes code
#sub unload {
#    my $self = shift;
#    my $class_name = $self->class_name;
#    return if ($class_name eq 'UR::Object::Type');  # A big no-no
#
#    # Unload instances of this class
#    if (substr($class_name, -6) ne '::Type') {
#        my @objs = $class_name->get();
#        my $ds = UR::Context->resolve_data_sources_for_class_meta_and_rule($self);
#        # Changed things with no data source can just be thrown away, right?
#        if ($ds) {
#            foreach (@objs) {
#                if ($_->__changes__) {
#                    die "Can't unload class object for $class_name, object instance with id ".$_->id." is changed";
#                }
#            }
#        }
#        $_->unload foreach @objs;
#    }
#
#    # unload the associated ghost class.  Note that ghosts don't have ghosts of their own
#    if (substr($class_name, -7,) ne '::Ghost') {
#        my $ghost_class = $class_name . '::Ghost';
#        my $ghost_class_meta = UR::Object::Type->is_loaded(class_name => $ghost_class);
#        if ($ghost_class_meta) {
#            eval { $ghost_class_meta->unload() };
#            if ($@) {
#                die "Can't unload class object for $class_name: unloading ghost class $ghost_class had errors:\n@_\n";
#            }
#        }
#    }
#
#    # Associated meta-class?
#    my $meta_class_object = UR::Object::Type->get(class_name => $self->meta_class_name);
#    eval {$meta_class_object->unload(); };
#    if ($@) {
#        die "Can't unload class object for $class_name: unloading meta class object had errors:\n@_\n";
#    }
#
#
#    # try unloading any child classes
#    foreach my $inh ( UR::Object::Inheritance->get(parent_class_name => $class_name) ) {
#        my $child_class = $inh->class_name;
#        my $child_class_meta = UR::Object::Type->get(class_name => $child_class);
#        eval { $child_class_meta->unload() };
#        if ($@) {
#            die "Can't unload class object for $class_name: unloading child class $child_class had errors:\n@_\n";
#        }
#    }
#
#    # Infrastructurey, hang-off data.  Things we can get via their class_name
#    foreach my $meta_type ( qw( UR::Object::Inheritance UR::Object::Property
#                                UR::Object::Reference 
#                                UR::Object::Property::Unique UR::Object::Property::ID
#                                UR::Object::Property::Calculated::From ) )
#    {
#        my @things = $meta_type->get(class_name => $class_name);
#        $_->unload() foreach @things;
#    }
#    # And once more for Indexes
#    {
#        my @things = UR::Object::Index->get(indexed_class_name => $class_name);
#         $_->unload() foreach @things;
#    }
#
#    $self->ungenerate();
#
#    $self->SUPER::unload();
#}
    
1;

