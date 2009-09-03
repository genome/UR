
=begin comment

# For bootstrapping reasons, the properties with default values also need to be listed in
# %class_property_defaults defined in UR::Object::Type::Initializer.  If you make changes
# to default values, please keep these in sync.
UR::Object::Class->define(
    class_name => 'UR::Object::Type',
    english_name => 'entity type',
    id_properties => ['class_name'],
    properties => [
        type_name                        => { type => 'VARCHAR2', len => 64 },
        class_name                       => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        data_source                      => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        doc                              => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        er_role                          => { type => 'VARCHAR2', len => 64, is_optional => 1, default_value => 'entity' },
        generated                        => { type => 'BOOL', len => undef, is_transient => 1 },
        is_abstract                      => { type => 'BOOL', len => undef, default_value => 0 },
        is_final                         => { type => 'BOOL', len => undef, default_value => 0 },
        is_singleton                     => { type => 'BOOL', len => undef, default_value => 0 },
        is_transactional                 => { type => 'BOOL', len => undef, default_value => 1 },
        short_name                       => { type => 'VARCHAR2', len => 16, is_optional => 1 },
        source                           => { type => 'VARCHAR2', len => 64, is_optional => 1 },
        table_name                       => { type => 'VARCHAR2', len => 64, is_optional => 1 },
    ],
    unique_constraints => [
        { properties => [qw/class_name/], sql => 'SUPER_FAKE_O2' },
    ],
);

=end comment

=cut

package UR::Object::Type;

use warnings;
use strict;

use Sys::Hostname;
use Cwd;
use Scalar::Util qw(blessed);

require UR;

our @ISA = qw(UR::Object);
our $VERSION = '2.1';

# This module implements define(), and most everything behind it.
use UR::Object::Type::Initializer;

# The methods used by the initializer to write accessors in perl.
use UR::Object::Type::AccessorWriter;

# The methods to extract/(re)create definition text in the module source file.
use UR::Object::Type::ModuleWriter;
use UR::Object::Type::DBICModuleWriter;

# These are used by the above modules as well.
our %meta_classes;
our $bootstrapping = 1;
our @partially_defined_classes;
our $pwd_at_compile_time = cwd();

sub get_namespace {
    my $self = shift;

    my $class_name = $self->class_name;
    my $pos = index($class_name,"::");
    return $class_name if ($pos < 1);  # The top-level namespace class is in its namespace

    my $namespace = substr($class_name,0,$pos);
    return $namespace;
}


sub data_source {
    my $self = shift;
    my $ds = $self->__data_source(@_);
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
        Carp::cluck("Attempt to access the data_source property of a class in $caller. "
            . "Calls should instead go to the current context:")
    }
    return $ds;
}

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
    my ($rule,%extra) = UR::BoolExpr->resolve_normalized_rule_for_class_and_params($class, @_);
    my %params = $rule->params_list;
    my $class_name = $params{class_name};
    return unless $class_name;
    return $class->_resolve_meta_class_name_for_class_name($class_name);
}


sub first_sub_classification_method_name {
    my $self = shift;
    
    # This may be one of many things which class meta-data should "inherit" from classes which 
    # its instances inherit from.  This value is set to the value found on the most concrete class
    # in the inheritance tree.

    return $self->{___first_sub_classification_method_name} if exists $self->{___first_sub_classification_method_name};
    
    $self->{___first_sub_classification_method_name} = $self->sub_classification_method_name;
    unless ($self->{___first_sub_classification_method_name}) {
        for my $parent_class ($self->ordered_inherited_class_objects) {
            last if ($self->{___first_sub_classification_method_name} = $parent_class->sub_classification_method_name);
        }
    }
    
    return $self->{___first_sub_classification_method_name};
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
                    return split($separator,$_[0])  
                }
            };
        }
        $self->{get_composite_id_decomposer} = $decomposer;
    }
    return $decomposer;
}

sub _resolve_composite_id_separator {   
    # TODO: make the class pull this from its parent at creation time
    # and only have it dump it if it differs from its parent
    my $self = shift;
    my $separator = "\t";
    for my $class_meta ($self, $self->ordered_inherited_class_objects) {
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


sub ordered_inherited_class_objects {
    map { __PACKAGE__->get($_) } shift->ordered_inherited_class_names;
}

*get_property_object_for_name = \&get_property_meta_by_name; 

sub get_property_meta_by_name {
    my ($self, $property_name) = @_;
    my $property;
    for my $class ($self->class_name, $self->ordered_inherited_class_names) {
        $property = UR::Object::Property->get(class_name => $class, property_name => $property_name);
        return $property if $property;
    }
    return;
}

# Return a closure that sort can use to sort objects by all their ID properties
# This should be the same order that an SQL query with 'order by ...' would return them
sub id_property_sorter {
    my $self = shift;

    unless ($self->{'_id_property_sorter'}) {
        my @id_properties = $self->id_property_names;
        $self->{'_id_property_sorter'} = sub ($$) {
            foreach my $property ( @id_properties ) {
                no warnings;   # don't print a warning about non-numeric comparison with <=> on the next line
                my $cmp = ($_[0]->$property <=> $_[1]->$property || $_[0]->$property cmp $_[1]->$property);
                return $cmp if $cmp;
            }
        };
    }

    return $self->{'_id_property_sorter'};
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
our %support_class_suffixes = map { $_ => 1 } qw/Set Viewer Ghost Iterator/;
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
        my %class_params = map { $_ => $subject_class_obj->$_ } $subject_class_obj->property_names;
        delete $class_params{generated};
        delete $class_params{sub_classification_property_name};
        delete $class_params{sub_classification_meta_class_name};
        delete $class_params{id};
        
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
                id_properties => \@id_property_names,
        );
        #print "D: $new_class_name" . Dumper(\%class_params);
        $class_obj = UR::Object::Type->define(%class_params);
    }
    elsif ($extension_for_support_class eq '::Set') {
        $class_obj = UR::Object::Set->_generate_class_for_member_class_name($subject_class_name);
    }
    else {
        Carp::confess() unless $extension_for_support_class;
        $class_obj = UR::Object::Type->define
        (
            class_name => $subject_class_name . "::" . $extension_for_support_class,
            is => \@parent_class_names,
            (
                $extension_for_support_class =~ /Edit/
                ?
                (
                    properties => [ $subject_class_obj->all_property_names ],
                    id_properties => [ $subject_class_obj->id_property_names ]
                )          
                :
                ()
            ),
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

sub has_property {
    my $self = shift;
    my $property_name = shift;
    return ($self->{has}{$property_name} ? 1 : '');
}

sub _load {
    my $class = shift;
    my $rule = shift;

    my $params = $rule->legacy_params_hash;

    # While core entity classes are actually loaded,
    # support classes dynamically generate for them as needed.
    # Examples are Acme::Employee::Viewer::emp_id, and Acme::Equipment::Ghost

    # Try to parse the class name.
    my $class_name = $params->{class_name};

    # See if the class autogenerates from another class.
    # i.e.: Acme::Foo::Bar might be generated by Acme::Foo
    unless ($class_name) {
        my $namespace = $params->{namespace};
        if (my $data_source = $params->{data_source}) {
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
        my @objs = map { $class->_load($rule_without_class_name->add_filter(class_name => $_)) } @$class_name;
        return $class->context_return(@objs);
    }
        
    # If the class is loaded, we're done.
    # This is an un-documented unique constraint right now.
    my $class_obj = $class->is_loaded(class_name => $class_name);
    return $class_obj if $class_obj;

    # Handle deleted classes.
    # This is written in non-oo notation for bootstrapping.
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
            $DB::single = 1;
            return $class_obj if $class_obj;
        } 

        my $base   = join("::", @parts[0 .. $suffix_pos-1]);
        my $suffix = join("::", @parts[$suffix_pos..$#parts]);

        # See if a class exists for the same name w/o the suffix.
        # This may cause this function to be called recursively for
        # classes like Acme::Equipment::Set::Viewer::upc_code,
        # which would fire recursively for three extensions of
        # Acme::Equipment.
        my $full_base_class_name = $prefix . ($base ? "::" . $base : "");
        my $base_class_obj = UR::Object::Type->get(class_name => $full_base_class_name);

        if ($base_class_obj)
        {
            # If so, that class may be able to generate a support
            # class.
            $class_obj = $full_base_class_name->generate_support_class($suffix);
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
        $path =~ s/$namespace_expected_module//g;
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

    local @INC = @INC;
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
        return;
    }

    if ($expected_directory and $expected_directory ne $found) {
        # not found in the specified location
        return;
    }

    do {
        local $SIG{__DIE__};
        local $SIG{__WARN__};
        eval "use $target_class";
    };

    if ($@) {
        Carp::confess("ERROR DYNAMICALLY LOADING CLASS $target_class from @INC\n$@");
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
    my @props = grep { $_->column_name } $self->get_property_objects();

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

    my @id_cols = $self->id_column_names();
    $sql .= ", PRIMARY KEY (" . join(',',@id_cols) . ")" if (@id_cols);

    # Should we also check for the unique properties?

    $sql .= ")";

    unless ($dbh->do($sql) ) {
        $self->error_message("Can't create table $table_name: ".$DBI::errstr."\nSQL: $sql");
        return undef;
    }

    1;
}







sub mk_attribute_value_accessor {
    my ($self, $class_name, $property_name) = @_;
   
    # defined on first use inside the closure 
    my $type_name;
    my $attribute_name;

    my $accessor = sub {
        my ($self, $new_value) = @_;
        
        unless ($type_name and $attribute_name) {
            my $class_object ||= UR::Object::Type->get (
                class_name => $class_name
            );
            my $property_object ||= UR::Object::Property->get (
                class_name     => $class_object->class_name,
                property_name => $property_name
            );
            $type_name = $class_object->type_name;
            $attribute_name = $property_object->attribute_name;
        }

        my $eav = GSC::EntityAttributeValue->get (
            type_name      => $type_name,
            entity_id      => $self->id,
            attribute_name => $attribute_name,
        );

        if ( @_ < 2) {
            # GET
            if ( $eav ) {
                return $eav->value;
            }
            else {
                return undef;
            }
        }
        else {
            # SET
            if ($eav) {
                my $old_value = $eav->value;

                if ( defined ($new_value) and $new_value ne "" ) {
                    # defined -> defined
                    return $old_value if ( $old_value eq $new_value );
                    $eav->value( $new_value );
                    $self->signal_change( $property_name, $old_value, $new_value );
                }
                else {
                    # defined -> undef
                    $eav->delete;
                    $self->signal_change( $property_name, $old_value, $new_value );
                }

                return $new_value;
            }
            else {
                if ( defined($new_value) ) {
                    # undef -> defined
                    $eav = GSC::EntityAttributeValue->create (
                        type_name      => $type_name,
                        entity_id      => $self->id,
                        attribute_name => $attribute_name,
                        value          => $new_value,
                    );
                    $self->signal_change( $property_name, undef, $new_value );
                    return $new_value;
                }
                else {
                    # undef -> undef
                    return undef;
                }
            }
        }
    };

    no strict 'refs';

    *{$class_name ."::$property_name"}  = $accessor;
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
    return ref($_[0]) ? $_[0] : $_[0]->get_class_object;
}



###################################################
#
# Methods which directly get data from the
# metadata system as efficiently as possible.
#
# Metadata about a class should be removed from
# the class itself, so we can track infrastructural
# requirements on a class right here.
#
###################################################

*has_subtypes = \&has_subclasses;

sub has_subclasses
{
    my $self = $_[0];
    unless (exists $_[0]->{has_subclasses})
    {
        if ($self->derived_type_names)
        {
            $self->{has_subclasses} = 1;
        }
        else
        {
            $self->{has_subclasses} = 0;
        }
    }
    return $_[0]->{has_subclasses};
}

###################################################
# methods that may go away when delegation is done
###################################################


##########################################
# Accessors for core metadata object sets
##########################################

sub get_property_objects
{
    my $self = _object(shift);
    my $table_name = $self->table_name;
    my @property_objects =
        UR::Object::Property->get( class_name => $self->class_name, @_ );
    return @property_objects;
}

sub get_id_objects
{
    my $self = _object(shift);
    my @id_objects =
        sort { $a->position <=> $b->position }
        UR::Object::Property::ID->get( class_name => $self->class_name );
    return @id_objects;
}

sub get_id_property_objects
{
    my $self = _object(shift);
    my @id_property_objects =
        map { UR::Object::Property->get(class_name => $_->class_name, attribute_name => $_->attribute_name) }
        $self->get_id_objects;
    if (@id_property_objects == 0) {
        @id_property_objects = $self->get_property_meta_by_name("id");
    }
    return @id_property_objects;
}

sub get_unique_objects
{
    my $self = _object(shift);
    my @unique_objects = UR::Object::Property::Unique->get( class_name => $self->class_name );
    return @unique_objects;
}

sub get_unique_property_objects
{
    my $self = _object(shift);
    my @unique_objects = $self->get_unique_objects;
    my @unique_property_objects =
        map { UR::Object::Property->get( class_name => $_->class_name, attribute_name => $_->attribute_name ) }
        @unique_objects;
    return @unique_property_objects;
}

sub get_columnless_property_objects
{
    my $self = _object(shift);
    my @columnless_property_objects =
        UR::Object::Property->get( class_name => $self->class_name, column_name => undef );
    return @columnless_property_objects;
}

sub get_reference_objects
{
    my $self = _object(shift);
    my @ref = UR::Object::Reference->is_loaded(class_name => $self->class_name, @_);
    return @ref;
}

sub get_referencing_objects
{
    my $self = _object(shift);
    my @ref = UR::Object::Reference->is_loaded(class_name => $self->class_name, @_);
    return @ref;
}

########################################
# Accessors for parent object sets
########################################

sub get_parent_class_objects {
    my $self = shift;
    return map { __PACKAGE__->get($_) } $self->parent_class_names
}

sub parent_class_names {
    my $self = shift;   
    return @{ $self->{is} };
}

########################################
# Accessors for inheritance object sets
########################################

sub get_inherited_class_objects {
    my $self = shift;
    return map { __PACKAGE__->get($_) } $self->ordered_inherited_class_names;
}

sub get_inherited_property_objects
{
    my $self = _object(shift);
    my @inherited_property_objects =
        map { $_->get_property_objects(@_) }
        $self->get_inherited_class_objects;
    return @inherited_property_objects;
}

sub get_inherited_id_property_objects
{
    my $self = _object(shift);
    my @inherited_id_property_objects =
        map { $_->get_id_property_objects }
        $self->get_inherited_class_objects;
    return @inherited_id_property_objects;
}

sub get_inherited_unique_property_objects
{
    my $self = _object(shift);
    my @inherited_unique_property_objects =
        map { $_->get_unique_property_objects }
        $self->get_inherited_class_objects;
    return @inherited_unique_property_objects;
}

sub get_inherited_columnless_property_objects
{
    my $self = _object(shift);
    my @inherited_columnless_property_objects =
        map { $_->get_columnless_property_objects }
        $self->get_inherited_class_objects;
    return @inherited_columnless_property_objects;
}

########################################
# Accessors for derived object sets
########################################

sub derived_type_names
{
    #Carp::confess();
    my $self = shift;
    my $type_name = $self->type_name;
    my @sub_type_links = UR::Object::Inheritance->get(parent_type_name => $type_name);
    my @sub_type_names = map { $_->type_name } @sub_type_links;
    return @sub_type_names;
}

sub derived_class_names
{
    #Carp::confess();
    my @derived_type_names = shift->derived_type_names;
    return map { UR::Object::Type->get($_)->class_name } @derived_type_names;
}

sub all_derived_type_names
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

sub all_derived_class_names
{
    #Carp::confess();
    my @all_derived_type_names = shift->all_derived_type_names;
    return map { UR::Object::Type->get($_)->class_name } @all_derived_type_names;
}

###############################################################
# Accessors for composite (directly and inherited) object sets
###############################################################

sub get_all_property_objects
{
    my $self = _object(shift);
    my @all_property_objects =
        ( $self->get_property_objects(@_), $self->get_inherited_property_objects(@_), );
    return @all_property_objects;
}

sub get_all_id_property_objects
{
    my $self = _object(shift);
    my @all_id_property_objects =
        ( $self->get_id_property_objects, $self->get_inherited_id_property_objects );
    return @all_id_property_objects;
}

sub get_all_unique_property_objects
{
    my $self = _object(shift);
    my @all_unique_property_objects =
        ( $self->get_inherited_unique_property_objects, $self->get_unique_property_objects );
    return @all_unique_property_objects;
}

sub get_all_columnless_property_objects
{
    my $self = _object(shift);
    my @all_columnless_property_objects =
        ( $self->get_inherited_columnless_property_objects, $self->get_columnless_property_objects );
    return @all_columnless_property_objects;
}

##############################
# Accessors for core metadata
##############################

sub instance_property_names
{
    my $self = _object(shift);
    my @property_names =
        map { $_->property_name }
        $self->get_property_objects;
    return @property_names;
}

sub column_names
{
    my $self = _object(shift);
    my @column_names =
        map { $_->column_name }
        $self->get_property_objects;
    return @column_names;
}

# see also UR::Object::id_properties
sub id_property_names {    
    my $self = _object(shift);
    my @id_by;
    unless ($self->{id_by} and @id_by = @{ $self->{id_by} }) {
        foreach my $parent ( @{ $self->{'is'} } ) {
            my $parent_class = UR::Object::Type->get(class_name => $parent);
            next unless $parent_class;
            @id_by = $parent_class->id_property_names;
            last if @id_by;
        }
    }   
    return @id_by;    
}

sub id_column_names
{
    my $self = _object(shift);
    my @id_column_names =
        map { $_->column_name }
        $self->get_id_property_objects;
    return @id_column_names;
}

sub unique_property_names
{
    my $self = _object(shift);
    my @unique_property_names =
        map { $_->property_name }
        $self->get_unique_property_objects;
    return @unique_property_names;
}

sub columnless_property_names
{
    my $self = _object(shift);
    my @columnless_property_names =
        map { $_->property_name }
        $self->get_columnless_property_objects;
    return @columnless_property_names;
}

sub inherited_property_names
{
    my $self = _object(shift);
    my @inherited_property_names =
        map { $_->property_names }
        $self->get_inherited_class_objects;
    return @inherited_property_names;
}

sub inherited_id_property_names
{
    my $self = _object(shift);
    my @inherited_id_property_names =
        map { $_->id_property_names }
        $self->get_inherited_class_objects;
    return @inherited_id_property_names;
}

sub inherited_id_column_names
{
    my $self = _object(shift);
    my @inherited_id_property_names =
        map { $_->id_column_names }
        $self->get_inherited_class_objects;
    return @inherited_id_property_names;
}

sub inherited_unique_property_names
{
    my $self = _object(shift);
    my @inherited_unique_property_names =
        map { $_->unique_property_names }
        $self->get_inherited_class_objects;
    return @inherited_unique_property_names;
}

sub inherited_column_names
{
    my $self = _object(shift);
    my @inherited_column_names =
        map { $_->column_names }
        $self->get_inherited_class_objects;
    return @inherited_column_names;
}

sub inherited_table_names
{
    my $self = _object(shift);
    my @inherited_table_names =
        grep { defined($_) }
        map { $_->table_name }
        $self->get_inherited_class_objects;
    return @inherited_table_names;
}

sub inherited_columnless_property_names
{
    my $self = _object(shift);
    my @inherited_columnless_property_names =
        map { $_->property_name }
        $self->get_inherited_columnless_property_objects;
    return @inherited_columnless_property_names;
}

sub all_table_names
{
    my $self = _object(shift);
    my @table_names =
        grep { defined($_) }
        ( $self->table_name, $self->inherited_table_names );
    return @table_names;
}

sub ordered_inherited_class_names {
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
        my $class_meta = UR::Object::Type->is_loaded($ancestor_class_name);
        Carp::confess("Can't find meta for $ancestor_class_name!") unless $class_meta;
        next unless $class_meta->{is};
        push @$ordered_inherited_class_names, @{ $class_meta->{is} };
        unshift @unchecked, $_ for reverse @{ $class_meta->{is} };
    }    
    #print "Set for $self->{class_name} to @$ordered_inherited_class_names\n";
    return @$ordered_inherited_class_names;
}

# old verstion gets only bc4nf properties
sub all_property_names {
    my $self = shift;
    
    if ($self->{_all_property_names}) {
        return @{ $self->{_all_property_names} };
    }
 
    my %seen = ();   
    my $all_property_names = $self->{_all_property_names} = [];
    for my $class_name ($self->class_name, $self->ordered_inherited_class_names) {
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
    
    #my @all_property_names =
    #    map { $_->property_name }
    #    $self->get_all_property_objects(@_);
    #return @all_property_names;
}

# new version gets everything, including "id" itself and object ref properties
sub all_property_type_names {
    my $self = shift;
    
    if ($self->{_all_property_type_names}) {
        return @{ $self->{_all_property_type_names} };
    }
    
    my $all_property_type_names = $self->{_all_property_type_names} = [];
    for my $class_name ($self->class_name, $self->ordered_inherited_class_names) {
        my $class_meta = UR::Object::Type->get($class_name);
        if (my $has = $class_meta->{has}) {            
            push @$all_property_type_names, sort keys %$has;
        }
    }
    return @$all_property_type_names;
}

sub all_column_names
{
    my $self = _object(shift);
    my @all_column_names =
        map { $_->column_name }
        $self->get_all_property_objects;
    return @all_column_names;
}

sub all_id_property_names {
    my $self = shift;
    unless ($self->{_all_id_property_names}) {
        my ($tmp,$last) = ('','');
        $self->{_all_id_property_names} = [
            grep { $tmp = $last; $last = $_; $tmp ne $_ }
            sort 
            map { @{ $_->{id_by} } } 
            map { __PACKAGE__->get($_) }
            ($self->class_name, $self->ordered_inherited_class_names)
        ];
    }
    return @{ $self->{_all_id_property_names} };
}

sub all_id_column_names
{
    my $self = _object(shift);
    my @all_id_column_names =
        map { $_->column_name }
        $self->get_all_id_property_objects;
    return @all_id_column_names;
}

sub all_unique_property_names
{
    my $self = _object(shift);
    my @all_unique_property_names =
        map { $_->property_name }
        $self->get_all_unique_property_objects;
    return @all_unique_property_names;
}

sub all_columnless_property_names
{
    my $self = _object(shift);
    my @all_columnless_property_names =
        map { $_->property_name }
        $self->get_all_columnless_property_objects;
    return @all_columnless_property_names;
}

#######################
# boolean-like methods
#######################

sub is_property {} # return property object

sub is_column {} # return property object
# more to come


# methods that use the following methods
# probably ought to be re-written to not use them

sub table_for_property
{
    my $self = _object(shift);
    die 'must pass a property_name to table_for_property' unless @_;
    my $property_name = shift;
    for my $class_object ( $self, $self->get_inherited_class_objects )
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

sub table_column_for_property
{
    my $self = _object(shift);
    die 'must pass a property_name to table_column_for_property' unless @_;
    my $property_name = shift;
    for my $class_object ( $self, $self->get_inherited_class_objects )
    {
        my $property_object = UR::Object::Property->get( class_name => $class_object->class_name, property_name => $property_name );
        if ( $property_object )
        {
            my $table_column;
            $table_column = join('.', $class_object->table_name, $property_object->column_name) if ( $class_object->table_name and $property_object->column_name );
            return $table_column;
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
    for my $class_object ( $self->get_inherited_class_objects )
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
    for my $class_object ( $self->get_inherited_class_objects )
    {
        my $cn = $class_object->class_name;
        $property_name = ${$cn . "::property_for_column"}{ $column_name };
        return $property_name if $property_name;
    }
    $class_name = $self->class_name;
    #die "$column_name is not a column for $class_name";
    return;
}

# not sure why this is here
sub get_property_object
{
    my $self = _object(shift);
    my %params = @_;
    warn 'you probably do not want to pass a type_name to get_property_object' if $params{ type_name };
    for my $co ( $self, $self->get_inherited_class_objects )
    {
        my $po = UR::Object::Property->get( type_name => $co->type_name, %params );
        return $po if $po;
    }
    return;
}

# ::Object unique_properties
sub unique_property_sets
{
    my $self = shift; 
    if ($self->{_unique_property_sets}) {
        return @{ $self->{_unique_property_sets} };
    }

    my $unique_property_sets = $self->{_unique_property_sets} = [];

    for my $class_name ($self->class_name, $self->ordered_inherited_class_names) {
        my $class_meta = UR::Object::Type->get($class_name);
        if ($class_meta->{constraints}) {            
            for my $spec (@{ $class_meta->{constraints} }) {
                push @$unique_property_sets, [ @{ $spec->{properties} } ] 
            }
        }
    }
    return @$unique_property_sets;

    my %all;
    for my $unique_object ( $self->get_unique_objects )
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


# Return a hashref where the keys are the SQL constraint names, and the
# values are listrefs holding the property names under that constraint
sub unique_property_set_hashref {
    my $self = shift;

    my $retval = {};
    foreach my $prop_set ( @{$self->{'constraints'}} ) {
        my @prop_names = @{$prop_set->{'properties'}};
        $retval->{$prop_set->{'sql'}} = \@prop_names;
    }
    return $retval;
}


# Used by the class meta meta data constructors to make changes in the 
# flat-format data stored in the class object's hash.  These should really
# only matter while running ur update

# These subscriptions get created in UR::Object::Type::Initializer
#UR::Object::Property->create_subscription(callback => \&_property_change_callback);
#UR::Object::Property::ID->create_subscription(callback => \&_id_property_change_callback);
#UR::Object::Property::Unique->create_subscription(callback => \&_unique_property_change_callback);
#UR::Object::Inheritance->create_subscription(callback => \&_inheritance_change_callback);

# Args are:
# 1) An UR::Object::Property object with attribute_name, class_name, id, property_name, type_name
# 2) The method called: create_object, load, 
# 3) An id?
sub _property_change_callback {
    my $property_obj = shift;
    my $method = shift;

    return if ($method eq 'load' || $method eq 'unload' || $method eq 'create_object' || $method eq 'delete_object');

    my $class = UR::Object::Type->get(class_name => $property_obj->class_name);
    my $property_name = $property_obj->property_name;

if ($method eq 'define') {
$DB::single=1;
1;
}
    if ($method eq 'create') {
        unless ($class->has_property($property_name)) {
            my @attr = qw( class_name attribute_name data_length data_type is_delegated is_optional property_name type_name );

            my %new_property;
            foreach my $attr_name (@attr ) {
                $new_property{$attr_name} = $property_obj->$attr_name();
            }
            $class->{'has'}->{$property_name} = \%new_property;
        }

    } elsif ($method eq 'delete') {
        delete $class->{'has'}->{$property_name};

    } elsif (exists $class->{'has'}->{$property_name}->{$method}) {
        my $old_val = shift;
        my $new_val = shift;
        $class->{'has'}->{$property_name}->{$method} = $new_val;
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

    return if ($method eq 'load' || $method eq 'unload' || $method eq 'create_object' || $method eq 'delete_object');

    my $class = UR::Object::Type->get(class_name => $property_obj->class_name);
    
    if ($method eq 'create') {
        # Position is 1-based, and the list embedded in the class object is 0-based
        my $pos = $property_obj->position;
        if ($pos > 0) {
            $pos--;
        } else {
            $pos = 0;
        }
        splice(@{$class->{'id_by'}}, $pos, 0, $property_obj->property_name);

    } elsif ($method eq 'delete') {
        my $property_name = $property_obj->property_name;
        for (my $i = 0; $i < @{$class->{'id_by'}}; $i++) {
            if ($class->{'id_by'}->[$i] eq $property_name) {
                splice(@{$class->{'id_by'}}, $i, 1);
                return;
            }
        }
        $DB::single = 1;
        Carp::confess("Internal data consistancy problem");

    } else {
        # Shouldn't get here since ID properties can't be changed, right?
        $DB::single = 1;
        Carp::confess("Shouldn't be here as ID properties can't change");
        1;
    }
}

        


sub _OLD_id_property_change_callback {
    my $property_obj = shift;
    my $method = shift;

    return if ($method eq 'load' || $method eq 'create_object' || $method eq 'delete_object');

    my $class = UR::Object::Type->get(class_name => $property_obj->class_name);
    my $pos = $property_obj->position;  # Position is 1-based, and the list embedded in the class is 0-based
    if ($pos > 0) {
        $pos--;
    } else {
        $pos = 0;
    }
    if ($method eq 'create' or
        ($method eq 'delete' and $class->{'id_by'}->[$pos] eq $property_obj->property_name) ) {

        if ($method eq 'create') {
            splice(@{$class->{'id_by'}}, $pos, 0, $property_obj->property_name);
            $pos++;
        } else {
            splice(@{$class->{'id_by'}}, $pos, 1);
        }

$DB::single=1;
        1;
        # Renumber the remaining id properties
        # FIXME  Renumbering these affects the ID properties of the inheritance
        # objects which is a big no-no.  Try skipping the renumbering and hopefully
        # the class rewriter will do the right thing given the flat data in the class
        # object.  Since this _should_ only be used within ur update, it shouldn't
        # be a problem.
        #for (my $i = $pos; $i < @{$class->{'id_by'}}; $i++) {
        #    my $property_name = $class->{'id_by'}->[$i];
        #    my $obj = UR::Object::Property::ID->is_loaded(class_name => $class->class_name,
        #                                                   property_name => $property_name);
        #    next unless $obj;
        #    $obj->position($i);
        #}
    } else {
        # Shouldn't get here since ID properties can't be changed, right?
        $DB::single = 1;
        Carp::confess("Shouldn't be here");
        1;
    }
}


sub _unique_property_change_callback {
    my $unique_obj = shift;
    my $method = shift;

    return if ($method eq 'load' || $method eq 'unload' || $method eq 'create_object' || $method eq 'delete_object');

    my $class = UR::Object::Type->get(class_name => $unique_obj->class_name);
    my $property_name = $unique_obj->property_name;

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
$DB::single=1;
        1;
    }
 
}

# Args here are:  
# 1) an UR::Object::Inheritance object with class_name, id, parent_class_name, type_name, parent_type_name
# 2) method called to fire this off:  create_object, load, 
# 3) Some kind of id property's value?
sub _inheritance_change_callback {
    my $inh_obj = shift;
    my $method = shift;

    return if ($method eq 'load' || $method eq 'unload' || $method eq 'create_object' || $method eq 'delete_object');

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


# Called from UR::Object::Inheritance::create to signal that a new inheritance object was created
sub _signal_new_inheritance {
my($self, $inh_obj) = @_;
    
Carp::confess("_signal_new_inheritance shouldn't be called anymore");
$DB::single=1;
    #$self->_new_ordered_flat_data($inh_object);
    my $prio = $inh_obj->inheritance_priority();

    splice(@{$self->{'is'}}, $prio, 0, $inh_obj->parent_class_name);
    for (my $i = $prio + 1; $i < @{$self->{'is'}}; $i++) {
        my $parent_class_name = $self->{'is'}->[$i];
        my $obj = UR::Object::Inheritance->is_loaded(class_name => $self->class_name,
                                                      parent_class_name => $parent_class_name);
        next unless $obj;  # not loaded yet
        $obj->inheritance_priority($i);
    }
    return 1;
}

sub _signal_new_property {
my($self,$prop_obj) = @_;

Carp::confess("_signal_new_property shouldn't be called anymore");
$DB::single=1;
    my @attr = qw( attribute_name data_length data_type is_delegated is_optional property_name type_name );
    my %new_property = ( class_name => $self->class_name );
        
    foreach my $attr_name (@attr ) {
        $new_property{$attr_name} = $prop_obj->$attr_name();
    }

    $self->{'has'}->{$prop_obj->property_name} = \%new_property;
    return 1;
}

sub _signal_new_id_property {
my($self,$prop_obj) = @_;

Carp::confess("_signal_new_id_property shouldn't be called anymore");
$DB::single=1;
    #$self->_new_ordered_flat_data($prop_object);
    my $pos = $prop_obj->position;

    splice(@{$self->{'id_by'}}, $pos, 0, $prop_obj->property_name);
    for (my $i = $pos + 1; $i < @{$self->{'id_by'}}; $i++) {
        my $property_name = $self->{'id_by'}->[$i];
        my $obj = UR::Object::Property::ID->get(class_name => $self->class_name,
                                                 property_name => $property_name);
        next unless $obj;
        $obj->position($i);
    }
    return 1;
}


sub _signal_new_unique_property {
my($self,$unique_obj) = @_;

Carp::confess("_signal_new_unique_property shouldn't be called anymore");
$DB::single=1;
    my %unique_constraints = map { $_->{'id'} => $_->{'properties'} } @{$self->{'constraints'}};
    my $unique_group = $unique_obj->unique_group;
    if ($unique_constraints{$unique_group}) {
        push(@{$unique_constraints{$unique_group}}, $unique_obj->property_name);
    } else {
        push(@{$self->{'constraints'}}, { sql => $unique_group, properties => [ $unique_obj->property_name ] });
    }
    return 1;
}


sub _signal_new_reference {
my($self,$ref_obj) = @_;

$DB::single=1;
    
}

#my %ordered_data_map = (
#        'UR::Object::Inheritance' =>  { class_key => 'is',
#                                       data_key  => 'parent_class_name',
#                                       order_key => 'inheritance_priority',
#                                     },
#        'UR::Object::Property::ID' => { class_key => 'has',
#                                       data_key  => 'property_name',
#                                       order_key => 'position',
#                                     },
#     );
#
#sub _new_ordered_flat_data {
#my($self,$object,$insert_data) = @_;
#
#    my $object_class_name = $object->class_name;
#    my $map = $ordered_data_map{$object_class_name};
#
#    my $position_getter = $map->{'order_key'};
#    my $pos = $object->$position_getter;
#
#    my $data_getter = $map->{'data_key'};
#    $insert_data ||=  $object->$data_getter;
#
#    my $self_key = $map->{'class_key'};
#    splice(@{$self->{$self_key}}, $pos, 0, $insert_data);
#
#    for (my $i = $pos + 1; $i < @{$self->{$self_key}}; $i++) {
#        my $obj_class = $object_class_name = $self->{$self_key}->[$i];
#        my $obj = $obj_class->is_loaded(class_name => $self->class_name,
#                                                      $data_getter => $obj_class);
#        next unless $obj;
#        $obj->$data_getter($i);
#    }
#}

   

    



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

sub load_all_on_first_access { 0 }

sub unique_properties_override { (['data_source','table_name']) }

sub signal_change {
    my $self = shift;
    my @rv = $self->SUPER::signal_change(@_);
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

1;

