package UR::Object::Type::ModuleWriter; # to help the installer

package UR::Object::Type; # hold methods for the class which cover Module Read/Write.

use strict;
use warnings;
require UR;
our $VERSION = "0.30"; # UR $VERSION;

our %meta_classes;
our $bootstrapping = 1;
our @partially_defined_classes;
our $pwd_at_compile_time = cwd();

sub resolve_class_description_perl {
    my $self = $_[0];
    
    no strict 'refs';
    my @isa = @{ $self->class_name . "::ISA" };
    use strict;

    unless (@isa) {
        #Carp::cluck("No isa for $self->{class_name}!?");
        my @i = ${ $self->is };
        my @parent_class_objects = map { UR::Object::Type->is_loaded(class_name => $_) } @i;
        die "Parent class objects not all loaded for " . $self->class_name unless (@i == @parent_class_objects);
        @isa = map { $_->class_name } @parent_class_objects;
    }

    unless (@isa) {
        #Carp::confess("FAILED TO SET ISA FOR $self->{class_name}!?");
        my @i = ${ $self->is };
        my @parent_class_objects = map { UR::Object::Type->is_loaded(class_name => $_) } @i;
                    
        unless (@i and @i == @parent_class_objects) {
            $DB::single=1;
            Carp::confess("No inheritance meta-data found for ( @i / @parent_class_objects)" . $self->class_name)
        }
        
        @isa = map { $_->class_name } @parent_class_objects;
    }

    my $class_name = $self->class_name;
    my @parent_classes = $self->parent_class_metas;
    my $has_table = $self->has_table;

    # For getting default values for some of the properties
    my $class_meta_meta = UR::Object::Type->get(class_name => 'UR::Object::Type');
    
    my $perl = '';
    
    unless (@isa == 1 and $isa[0] =~ /^UR::Object|UR::Entity$/ ) {
        $perl .= "    is => " . (@isa == 1 ? "[ '@isa' ],\n" : "[ qw/@isa/ ],\n");
    }
    $perl .= "    type_name => '" . $self->type_name . "',\n" unless $self->type_name eq $class_name;
    $perl .= "    table_name => " . ($self->table_name ? "'" . $self->table_name . "'" : 'undef') . ",\n" if $self->data_source_id;
    $perl .= "    is_abstract => 1,\n" if $self->is_abstract;
    $perl .= "    er_role => '" . $self->er_role . "',\n" if ($self->er_role and ($self->er_role ne $class_meta_meta->property_meta_for_name('er_role')->default_value));

    # Meta-property attributes
    my @property_meta_property_names;
    my @property_meta_property_strings;
    if ($self->{'attributes_have'}) {
        @property_meta_property_names = sort { $self->{'attributes_have'}->{$a}->{'position_in_module_header'}
                                                 <=>
                                               $self->{'attributes_have'}->{$b}->{'position_in_module_header'} }
                                            keys %{$self->{'attributes_have'}};
        foreach my $meta_name ( @property_meta_property_names ) {
            my $this_meta_struct = $self->{'attributes_have'}->{$meta_name};

            # The attributes_have structure gets propogated to subclasses, but it only needs to appear
            # in the class definition of the most-parent class
            my $expected_name = $class_name . '::attributes_have';
            next unless ( $this_meta_struct->{'is_specified_in_module_header'} eq $expected_name);

            # We want these to appear first
            my @this_meta_properties;
            push @this_meta_properties, sprintf("is => '%s'", $this_meta_struct->{'is'}) if (exists $this_meta_struct->{'is'});
            push @this_meta_properties, sprintf("is_optional => %d", $this_meta_struct->{'is_optional'}) if (exists $this_meta_struct->{'is_optional'});

            foreach my $key ( sort keys %$this_meta_struct ) {
                next if grep { $key eq $_ } qw( is is_optional is_specified_in_module_header position_in_module_header );  # skip the ones we've already done
                my $value = $this_meta_struct->{$key};
                
                my $format = $self->_is_number($value) ? "%s => %s" : "%s => '%s'";
                push @this_meta_properties, sprintf($format, $key, $value);
            }
            push @property_meta_property_strings, "$meta_name => { " . join(', ', @this_meta_properties) . " },";
        }
    }
    if (@property_meta_property_strings) {
        $perl .= "    attributes_have => [\n        " . 
                 join("\n        ", @property_meta_property_strings) .
                 "\n    ],\n";
    }

    if (exists $self->{'first_sub_classification_method_name'}) {
        # This gets overridden by UR::Object::Type to cache the value it finds from parent
        # classes in __first_sub_classification_method_name, so we can't just get the
        # property through the normal channels
        $perl .= "    first_sub_classification_method_name => '" . $self->{'first_sub_classification_method_name'} ."',\n";
    }
            
    # These property names are either written in other places in this sub, or shouldn't be written out
    my %addl_property_names = map { $_ => 1 } $self->__meta__->all_property_type_names;
    my @specified = qw/is class_name type_name table_name id_by er_role is_abstract generated data_source_id schema_name doc namespace id first_sub_classification_method_name property_metas pproperty_names id_property_metas meta_class_name/;
    delete @addl_property_names{@specified};
    for my $property_name (sort keys %addl_property_names) {
        my $property_obj = $class_meta_meta->property_meta_for_name($property_name);
        next if ($property_obj->is_calculated or $property_obj->is_delegated);

        my $property_value = $self->$property_name;
        my $default_value = $property_obj && $property_obj->default_value;
        # If the property is set on the class object
        # and both the value and default are numeric and numerically different,
        #     or stringly different than the default
        no warnings qw( numeric uninitialized );
        if ( defined $property_value and
             ( ($property_value + 0 eq $property_value and
                $default_value + 0 eq $default_value and
                $property_value != $default_value) 
               or
                ($property_value ne $default_value)
             )
           ) {
                # then it should show up in the class definition
                $perl .= "    $property_name => '" . $self->$property_name . "',\n";
           }
    }

    my %properties_by_section;
    my %id_property_names = map { $_ => 1 } $self->direct_id_property_names;
    my @properties = $self->direct_property_metas;
    foreach my $property_meta ( @properties ) {
        my $mentioned_section = $property_meta->is_specified_in_module_header;
        next unless $mentioned_section;  # skip implied properites
        ($mentioned_section) = ($mentioned_section =~ m/::(\w+)$/);
         
        if (($mentioned_section and $mentioned_section eq 'id_implied')
            or $id_property_names{$property_meta->property_name}) {

            push @{$properties_by_section{'id_by'}}, $property_meta;

        } elsif ($mentioned_section) {
            push @{$properties_by_section{$mentioned_section}}, $property_meta;
  
        } else {
            push @{$properties_by_section{'has'}}, $property_meta;
        }
    }

    my %sections_seen;
    foreach my $section ( ( 'id_by', 'has', 'has_many', 'has_optional', keys(%properties_by_section) ) ) {
        next unless ($properties_by_section{$section});
        next if ($sections_seen{$section});
        $sections_seen{$section} = 1;

        # New properites (will have position_in_module_header == undef) should go at the end
        my @properties = sort { my $pos_a = defined($a->{'position_in_module_header'})
                                            ? $a->{'position_in_module_header'}
                                            : 1000000;
                                my $pos_b = defined($b->{'position_in_module_header'})
                                            ? $b->{'position_in_module_header'}
                                            : 1000000;
                                $pos_a <=> $pos_b;
                              }
                              @{$properties_by_section{$section}};
        
        my $section_src = '';
        my $max_name_length = 0;
        my $multi_line_indent = '';
        foreach my $property_meta ( @properties ) {
            my $name = $property_meta->property_name;
            $max_name_length = length($name) if (length($name) > $max_name_length);
        }
        # 14 is the 8 spaces at the start of the $line, plus ' => { '
        $multi_line_indent = ' ' x ($max_name_length + 14);
        foreach my $property_meta ( @properties ) {
            my $name = $property_meta->property_name;
            my @fields = $self->_get_display_fields_for_property(
                                        $property_meta,
                                        has_table => $has_table,
                                        section => $section,
                                        attributes_have => \@property_meta_property_names);

            foreach ( @fields ) {
                s/\n/\n$multi_line_indent/;
            }
            my $line = "        "
                . $name . (" " x ($max_name_length - length($name)))
                . " => { "
                . join(", ", @fields)
                . " },\n";

            $section_src .= $line;
        }

        $perl .= "    $section => [\n$section_src    ],\n";
    }

    my $unique_groups = $self->unique_property_set_hashref;
    if ($unique_groups and keys %$unique_groups) {

        $perl .= "    unique_constraints => [\n";
        for my $unique_group_name (keys %$unique_groups) {
            my $property_names = join(' ', sort { $a cmp $b } @{ $unique_groups->{$unique_group_name}});
            $perl .= "        { "
                . "properties => [qw/$property_names/], "
                . "sql => '" . $unique_group_name . "'"
                . " },\n";
        }
        $perl .= "    ],\n";
    }

    $perl .= "    schema_name => '" . $self->schema_name . "',\n" if $self->schema_name;
    $perl .= "    data_source => '" . $self->data_source_id . "',\n" if $self->data_source_id;

    my $doc = $self->doc;
    if (defined($doc)) {
        $doc = Dumper($doc);
        $doc =~ s/\$VAR1 = //;
        $doc =~ s/;\s*$//;
    }
    $perl .= "    doc => $doc,\n" if defined($doc);
    return $perl;
}

sub resolve_module_header_source {
    my $self = shift;
    my $class_name = $self->class_name;
    my $perl = "class $class_name {\n";
    $perl .= $self->resolve_class_description_perl;
    $perl .= "};\n";
    return $perl;
}

my $next_line_prefix = "\n";
my $deep_indent_prefix = "\n" . (" " x 55);

sub _get_display_fields_for_property {
    my $self = shift;
    my $property = shift;
    my %params = @_;
    
    if (not $property->is_specified_in_module_header) {
        # we omit showing implied properties which have no additional data,
        # unless they have their own docs, a specified column, etc.
        return();
    }    
    
    my @fields;    
    my %seen;
    my $property_name = $property->property_name;
    
    my $type = $property->data_type;
    if ($type) {
        push @fields, "is => '$type'" if $type;
        $seen{'is'} = 1;
    }
    
    if (defined($property->data_length) and length($property->data_length)) {
        push @fields, "len => " . $property->data_length;
        $seen{'data_length'} = 1;
    }
    
    #$line .= "references => '???', ";
    if ($property->is_legacy_eav) { 
        # temp hack for entity attribute values
        #push @fields, "delegate => { via => 'eav_" . $property->property_name . "', to => 'value' }";
        push @fields, "is_legacy_eav => 1";                
        $seen{'is_legacy_eav'} = 1;
    }
    elsif ($property->is_delegated) {
        # do nothing
        $seen{'is_delegated'} = 1;
    }
    elsif ($property->is_calculated) {
        my @calc_fields;
        if (my $calc_from = $property->calculate_from) {
            if ($calc_from and @$calc_from == 1) {
                push @calc_fields, "calculate_from => '" . $calc_from->[0] . "'";
            } elsif ($calc_from) {
                push @calc_fields, "calculate_from => [ '" . join("', '", @$calc_from) . "' ]";
            }
        }

        my $calc_source;
        foreach my $calc_type ( qw( calculate calculate_sql calculate_perl calculate_js ) ) {
            if ($property->$calc_type) {
                $calc_source = 1;
                push @calc_fields, "$calc_type => q(" . $property->$calc_type . ")";
            }
        }

        push @calc_fields, 'is_calculated => 1' unless ($calc_source);

        push @fields, join(",$next_line_prefix", @calc_fields);
        $seen{'is_calculated'} = 1;
    } 
    elsif ($params{has_table} && ! $property->is_transient) {
        unless ($property->column_name) {
            die("no column for property on class with table: " . $property->property_name .
                " class: " . $self->class_name . "?");
        }
        if (uc($property->column_name) ne uc($property->property_name)) {
            push @fields,  "column_name => '" . $property->column_name . "'";
        }
        $seen{'column_name'} = 1;
    }

    if (defined($property->default_value)) {
        my $value = $property->default_value;
        if (! $self->_is_number($value)) {
            $value = "'$value'";
        }
        push @fields, "default_value => $value";
        $seen{'default_value'} = 1;
    }
    
    my $implied_property = 0;
    if (defined($property->implied_by) and length($property->implied_by)) { 
        push @fields,  "implied_by => '" . $property->implied_by . "'";
        $implied_property = 1;
        $seen{'implied_by'} = 1;
    }

    if (my @id_by = eval { $property->get_property_name_pairs_for_join }) {
        push @fields, "id_by => " 
            . (@id_by > 1 ? '[ ' : '')
            . join(", ", map { "'" . $_->[0] . "'" } @id_by)
            . (@id_by > 1 ? ' ]' : '');
        $seen{'get_property_name_pairs_for_join'} = 1;

        if (defined $property->id_class_by) {
            push @fields, sprintf("id_class_by => '%s'", $property->id_class_by);
        }
    }

    if ($property->via) {
        push @fields, "via => '" . $property->via . "'";
        $seen{'via'} = 1;
        if ($property->to and $property->to ne $property->property_name) {
            push @fields, "to => '" . $property->to . "'";
            $seen{'to'} = 1;
        }

        if ($property->is_mutable) {
            # via properties are not usually mutable
            push @fields, 'is_mutable => 1';
        }
    }
    if ($property->reverse_as) {
        push @fields, "reverse_as => '" . $property->reverse_as . "'";
        $seen{'reverse_as'} = 1;
    }

    if ($property->constraint_name) {
        push @fields, "constraint_name => '" . $property->constraint_name . "'";
        $seen{'constraint_name'} = 1;
    }

    if ($property->where) {
        my @where_parts = ();

        my @where = @{ $property->where };
        while (@where) {
            my $prop_name = shift @where;
            my $comparison = shift @where;
            if (! ref($comparison)) {
                # It's a strictly equals comparison.
                # wrap it in quotes...
                $comparison = "'$comparison'";

            } elsif (ref($comparison) eq 'HASH') {
                # It's a more complicated operator
                my @operator_parts = ();
                foreach my $key ( 'operator', 'value', keys %$comparison ) {
                    if ($comparison->{$key}) {
                        if (ref($comparison->{$key})) {
                            my $class_name = $property->class_name;
                            Carp::croak("Modulewriter doesn't know how to handle property $property_name of class $class_name.  Its 'where' has a non-scalar value for the '$key' key");
                        }
                        push @operator_parts, "$key => '" . delete($comparison->{$key}) . "'";
                    }
                }
                $comparison = '{ ' . join(', ', @operator_parts) . ' } ';
            } else {
                my $class_name = $property->class_name;
                Carp::croak("Modulewriter doesn't know how to handle property $property_name of class $class_name.  Its 'where' is not a simple scalar or hashref");
            }
            push @where_parts, "$prop_name => $comparison";
        }
        push @fields, 'where => [ ' . join(', ', @where_parts) . ' ]';
    }

    if (my $values_arrayref = $property->valid_values) {
        $seen{'valid_values'} = 1;
        my $value_string = Data::Dumper->new([$values_arrayref])->Terse(1)->Indent(0)->Useqq(1)->Dump;
        push @fields, "valid_values => $value_string";
    }

    # All the things like is_optional, is_many, etc
    # show only true values, false is default
    # section can be things like 'has', 'has_optional' or 'has_transient_many_optional'
    my $section = $params{'section'};
    $section =~ m/^has_(.*)/;
    my @sections = split('_',$1 || '');
    
    for my $std_field_name (qw/optional abstract transient constant class_wide many deprecated/) {
        $seen{$property_name} = 1;
        next if (grep { $std_field_name eq $_ } @sections); # Don't print is_optional if we're in the has_optional section
        my $property_name = "is_" . $std_field_name;
        push @fields, "$property_name => " . $property->$property_name if $property->$property_name;
    }


    foreach my $meta_property ( @{$params{'attributes_have'}} ) {
        my $value = $property->{$meta_property};
        if (defined $value) {
            my $format = $self->_is_number($value) ? "%s => %s" : "%s => '%s'";
            push @fields, sprintf($format, $meta_property, $value);
        }
    }
    
    my $desc = $property->doc;
    if ($desc && length($desc)) {
        $desc =~ s/([\$\@\%\\\"])/\\$1/g;
        $desc =~ s/\n/\\n/g;
        push @fields, $next_line_prefix . "doc => '$desc'";
    }
    
    return @fields;
}

sub module_base_name {
    my $file_name = shift->class_name;
    $file_name =~ s/::/\//g;
    $file_name .= ".pm";
    return $file_name;
}

sub module_path {
    my $self = shift;
    my $base_name = $self->module_base_name;
    my $path = $INC{$base_name};
    return _abs_path_relative_to_pwd_at_compile_time($path) if $path;
    #warn "Module $base_name is not in \%INC!\n";

    my $namespace;
    my $first_slash = index($base_name, '/');
    if ($first_slash >= 0) {
        # Normal case...
        $namespace = substr($base_name, 0, $first_slash);
        $namespace .= ".pm";
    } else {
        # This module must _be_ the namespace
        $namespace = $base_name;
    }

    for my $dir (map { _abs_path_relative_to_pwd_at_compile_time($_) } grep { -d $_ } @INC) {
        if (-e $dir . "/" . $namespace) {
            #warn "Found $base_name in $dir...\n";
            my $try_path = $dir . '/' . $base_name;
            return $try_path;
        }
    }
    return;
    #Carp::confess("Failed to find a module path for class " . $self->class_name);
}
            
sub _abs_path_relative_to_pwd_at_compile_time { # not a method 
    my $path = shift;
    if ($path !~ /^[\/\\]/) {
        $path = $pwd_at_compile_time . '/' . $path;
    } 
    my $path2 = Cwd::abs_path($path);
#    Carp::confess("$path abs is undef?") if not defined $path2;
    return $path2;
}


sub module_directory {
    my $self = shift;
    my $base_name = $self->module_base_name;
    my $path = $self->module_path;
    return unless defined($path) and length($path);
    unless ($path =~ s/$base_name$//) {
        Carp::confess("Failed to find base name $base_name at the end of path $path!")
    }
    return $path;
}

sub module_source_lines {
    my $self = shift;
    my $file_name = $self->module_path;
    my $in = IO::File->new("<$file_name");
    unless ($in) {
        return (undef,undef,undef);
    }
    my @module_src = <$in>;
    $in->close;
    return @module_src
}

sub module_source {
    join("",shift->module_source_lines);
}

sub module_header_positions {
    my $self = shift;

    my @module_src = $self->module_source_lines;
    my $namespace = $self->namespace;
    my $class_name = $self->class_name;
    
    unless ($self->namespace) {
        die "No namespace on $self->{class_name}?"
    }    
    
    $namespace = 'UR' if $namespace eq $self->class_name;

    my $state = 'before';
    my ($begin,$end,$use);
    for (my $n = 0; $n < @module_src; $n++) {
        my $line = $module_src[$n];        
        if ($state eq 'before') {
            if ($line and $line =~ /^use $namespace;/) {
                $use = $n;
            }
            if (
                $line and (
                    $line =~ /^define UR::Object::Type$/
                    or $line =~ /^(App|UR)::Object::(Type|Class)->(define|create)\($/
                    or $line =~ /^class\s*$class_name\b/
                )
            ) {
                $begin = $n;
                $state = 'during';
            }
            else {

            }
        }
        elsif ($state eq 'during') {
            my $old_meta_src .= $line;  # FIXME this dosen't appear anywhere else??
            if ($line =~ /^(\)|\}|);\s*$/) {
                $end = $n;
                $state = 'after';
            }
        }
        #elsif ($state eq 'after') {
        #
        #}
    }

    # cache
    $self->{module_header_positions} = [$begin,$end,$use];

    # return
    return ($begin,$end,$use);
}

sub module_header_source_lines {
    my $self = shift;
    my ($begin,$end,$use) = $self->module_header_positions;
    my @src = $self->module_source_lines;
    return unless $end;
    @src[$begin..$end];
}

sub module_header_source {
    join("",shift->module_header_source_lines);
}

sub rewrite_module_header {
    use strict;
    use warnings;

    my $self = shift;
    my $package = $self->class_name;

    # generate new class metadata
    my $new_meta_src = $self->resolve_module_header_source;
    unless ($new_meta_src) {
        die "Failed to generate source code for $package!";
    }

    my ($begin,$end,$use) = $self->module_header_positions;
    
    my $namespace = $self->namespace;
    $namespace = 'UR' if $namespace eq $self->class_name;
    
    unless ($namespace) {
        ($namespace) = ($package =~ /^(.*?)::/);
    }
    $new_meta_src = "use $namespace;\n" . $new_meta_src unless $use;

    # determine the path to the module
    # this may not exist
    my $module_file_path = $self->module_path;

    # temp safety hack
    if ($module_file_path =~ "/gsc/scripts/lib") {
        Carp::confess("attempt to write directly to the app server!");
    }

    # determine the new source for the module
    my @module_src;
    my $old_file_data;
    if (-e $module_file_path) {
        # rewrite the existing module

        # find the old positions of the module header
        @module_src = $self->module_source_lines;

        # cleanup legacy cruft
        unless ($namespace eq 'UR') {
            @module_src = map { ($_ =~ m/^use UR;/?"":$_) } @module_src;
        }

        if (!grep {$_ =~ m/^use warnings;/} @module_src) {
            $new_meta_src = "use warnings;\n" . $new_meta_src;
        }

        if (!grep {$_ =~ m/^use strict;/} @module_src) {
            $new_meta_src = "use strict;\n" . $new_meta_src;
        }

        # If $begin and $end are undef, then module_header_positions() didn't find any
        # old code and we're inserting all brand new stuff.  Look for the package declaration
        # and insert after that.
        my $len;
        if (defined $begin || defined $end) {
            $len = $end-$begin+1;
        } else {
            # is there a more fool-proof way to find it?
            for ($begin = 0; $begin < $#module_src; ) {
                last if ($module_src[$begin++] =~ m/package\s+$package;/);
            }
            $len = 0;
        }

        # replace the old lines with the new source
        # note that the inserted "row" is multi-line, but joins nicely below...
        splice(@module_src,$begin,$len,$new_meta_src);
        
        my $f = IO::File->new($module_file_path);
        $old_file_data = join('',$f->getlines);
        $f->close();
    }
    else {
        # write new module source

        # put =cut marks around it if this is a special metadata class
        # the definition at the top is non-functional for bootstrapping reasons
        if ($meta_classes{$package}) {
            $new_meta_src = "=cut\n\n$new_meta_src\n\n=cut\n\n";
            $self->warning_message("Meta package $package");
        }

        @module_src = join("\n",
            "package " . $self->class_name . ";",
            "",
            "use strict;",
            "use warnings;",
            "",
            $new_meta_src,
            "1;",
            ""
        );
    }

    $ENV{'HOST'} ||= '';
    my $temp = "$module_file_path.$$.$ENV{HOST}";
    my $temp_dir = $module_file_path;
    $temp_dir =~ s/\/[^\/]+$//;
    unless (-d $temp_dir) {
        print "mkdir -p $temp_dir\n";
        system "mkdir -p $temp_dir";
    }
    my $out = IO::File->new(">$temp");
    unless ($out) {
        die "Failed to create temp file $temp!";
    }
    for (@module_src) { $out->print($_) };
    $out->close;

    my $rv = system qq(perl -e 'eval `cat $temp`' 2>/dev/null 1>/dev/null);
    $rv /= 255;
    if ($rv) {
        die "Module is not compilable with new source!";
    }
    else {
        unless (rename $temp, $module_file_path) {
            die "Error renaming $temp to $module_file_path!";
        }
    }

    UR::Context::Transaction->log_change($self, ref($self), $self->id, 'rewrite_module_header', Data::Dumper::Dumper{path => $module_file_path, data => $old_file_data});

    return 1;
}


# TODO: move to UR::Util
sub _is_number {
    my($self,$value) = @_;
    no warnings 'numeric';
    my $is_number = ($value + 0) eq $value;
    return $is_number;
}


1;

=pod

=head1 NAME

UR::Object::Type::ModuleWriter - Helper module for UR::Object::Type responsible for writing Perl modules

=head1 DESCRIPTION

Subroutines within this module actually live in the UR::Object::Type
namespace;  this module is just a convienent place to collect them.  The
Module Writer is used by the class updater system (L<(UR::Namespace::Command::Update::Classes>
and 'ur update classes) to add, remove and alter the Perl modules behind
the classes within a Namespace.  

=head1 METHODS

=over 4

=item resolve_module_header_source

  $classobj->resolve_module_header_source();

Returns a string that represents a fully-formed class definition the the
given class metaobject $classobj.

=item resolve_class_description_perl

  $classobj->resolve_class_description_perl()

Used by resolve_module_header_source().  This method inspects all the
applicable properties of the class metaobject and builds up a string that
gets inserted between the {...} of the class definition string.

=item rewrite_module_header

  $classobj->rewrite_module_header();

This method rewrites an existing Perl module file in place for the class
metaobject, or creates a new file if one does not already exist.

=item module_base_name

Returns the pathname of the class's module relative to the top level directory
of that class's Namespace.

=item module_path

Returns the fully qualified pathname of the class's module.

=item module_source_lines

Returns the text of the class's Perl module as a list of strings.

=item module_source

Returns the text of the class's Perl module as a single string.

=item module_header_positions

Returns a 3-element list ($begin, $end, $use) where $begin is the line number
where the class header begins.  $end is the line number where it ends.  $use
is the line number where the module declares that it use's a Namespace.

=item module_header_source_lines

Returns the text of the class's Perl module source where the class definition
is as a list of strings.

=item module_header_source

Returns the text of the class's Perl module source where the class definition
is as a single string.

=back

=head1 SEE ALSO

UR::Object::Type, UR::Object::Type::Initializer

=cut


