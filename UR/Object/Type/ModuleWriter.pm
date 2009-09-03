
package UR::Object::Type::ModuleWriter; # to help the installer

package UR::Object::Type; # hold methods for the class which cover Module Read/Write.

use strict;
use warnings;

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
        my @i = UR::Object::Inheritance->get(
            class_name => $self->class_name
        );
        my @parent_class_objects = map { UR::Object::Type->is_loaded(class_name => $_->parent_class_name) } @i;
        die "Parent class objects not all loaded for " . $self->class_name unless (@i == @parent_class_objects);
        @isa = map { $_->class_name } @parent_class_objects;
    }

    unless (@isa) {
        #Carp::confess("FAILED TO SET ISA FOR $self->{class_name}!?");
        my @i = UR::Object::Inheritance->get(
            class_name => $self->class_name
        );
        my @parent_class_objects = 
            map { UR::Object::Type->is_loaded(class_name => $_->parent_class_name) } @i;
                    
        unless (@i and @i == @parent_class_objects) {
            $DB::single=1;
            Carp::confess("No inheritance meta-data found for ( @i / @parent_class_objects)" . $self->class_name)
        }
        
        @isa = map { $_->class_name } @parent_class_objects;
    }

    my $class_name = $self->class_name;
    my @parent_classes = $self->get_parent_class_objects;
    my $has_table = $self->has_table;

    # For getting default values for some of the properties
    my $class_meta_meta = UR::Object::Type->get(class_name => 'UR::Object::Type');
    
    my $perl = '';
    
    unless (@isa == 1 and $isa[0] =~ /^UR::Object|UR::Entity$/ ) {
        $perl .= "    is => " . (@isa == 1 ? "['@isa'],\n" : "[qw/@isa/],\n");
    }
    $perl .= "    type_name => '" . $self->type_name . "',\n" unless $self->type_name eq $class_name;
    $perl .= "    table_name => " . ($self->table_name ? "'" . $self->table_name . "'" : 'undef') . ",\n" if $self->data_source;
    $perl .= "    is_abstract => 1,\n" if $self->is_abstract;
    $perl .= "    er_role => '" . $self->er_role . "',\n" if ($self->er_role and ($self->er_role ne $class_meta_meta->get_property_object(property_name => 'er_role')->default_value));

    # These property names are either written in other places in this sub, or shouldn't be written out
    my %addl_property_names = map { $_ => 1 } $self->get_class_object->all_property_type_names;
    my @specified = qw/class_name type_name table_name id_by er_role is_abstract generated data_source schema_name doc namespace id/;
    delete @addl_property_names{@specified};
    for my $property_name (sort keys %addl_property_names) {
        my $property_obj = $class_meta_meta->get_property_object(property_name => $property_name);
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

    my %properties_seen;
    my %implied_properties;
    my %properties_printed;
    for my $group ('id_by','has') {
        my $properties_src = "";
        my @properties_to_list;
        if ($group eq 'id_by') {
            @properties_to_list = 
                sort {
                    my $a_pos = (ref($a) eq 'UR::Object::Property::ID' ? $a->position : $a->rank);
                    my $b_pos = (ref($b) eq 'UR::Object::Property::ID' ? $b->position : $b->rank);
                    $a_pos <=> $b_pos;
                }
                map { 
                    UR::Object::Property::ID->get(class_name => $class_name, property_name => $_),
                    UR::Object::Reference::Property->get(class_name => $class_name, property_name => $_)
                } 
                $self->id_property_names;
                
            if (@isa == 1
                and @properties_to_list == 2 
                and $properties_to_list[1]->isa('UR::Object::Reference::Property') 
                and $properties_to_list[1]->get_reference->r_class_name eq $isa[0]
            ) {
                # the id is a fk to the parent class' ID: this is really a relationship to self                
                @properties_to_list = ($properties_to_list[0]->get_property);
            }
            else {
                @properties_to_list = map { ref($_) eq 'UR::Object::Reference::Property' ? $_->get_reference : $_->get_property } @properties_to_list; 
            }
        }
        else {
            @properties_to_list = (
                UR::Object::Property->get(class_name => $self->class_name),
                UR::Object::Reference->get(class_name => $self->class_name)
            );
        }
        
        my $max_name_length = 0;        
        for my $p (@properties_to_list) {
            my $name = ($p->isa("UR::Object::Property") ? $p->property_name : $p->delegation_name);
            $max_name_length = length($name) if $max_name_length < length($name);
            if (my $other = $properties_seen{$name}) {
                if ($other->isa("UR::Object::Reference")) {
                    # a non-reference takes precedence
                    $properties_seen{$name} = $p;
                }
                else {
                    # skip/duplicate
                    next;
                }
            }
            else {
                $properties_seen{$name} = $p;
            }
            
            my @id_by;
            if ($p->isa("UR::Object::Property")) {
                @id_by = $p->id_by_property_links;            
            }
            else {
                @id_by = $p->property_link_names;            
            }
            for (@id_by) {
                $implied_properties{$_} = $name;                
            }            
        }
        
        @properties_to_list = 
            sort {
                my $name_a = ($a->isa("UR::Object::Property") ? $a->property_name : $a->delegation_name);
                my $name_b = ($b->isa("UR::Object::Property") ? $b->property_name : $b->delegation_name);
                ($name_a cmp $name_b);
            } @properties_to_list;
        
        for my $property (@properties_to_list) {
            my $name = ($property->isa("UR::Object::Property") ? $property->property_name : $property->delegation_name);
            unless ($property) {
                die "No $name?\n";
            }
            next if $properties_printed{$name};
            
            my @fields;
            
            if ($property->isa("UR::Object::Reference")) {
                #print Data::Dumper::Dumper("got reference for $class_name: $property->{id}");
                my $type = $property->r_class_name;
                push @fields, "is => '$type'";            
                if ($property->property_link_names == 1) {
                    push @fields, "id_by => '" . ($property->property_link_names)[0] . "'";
                }
                else {
                    push @fields, "id_by => [" . join(", ", map { "'$_'" } $property->property_link_names) . "]";
                }
            
                if ($property->constraint_name) {
                    push @fields, "constraint_name => '" . $property->constraint_name . "'";
                }
            }
            else {
                @fields = $self->_get_display_fields_for_property($property, has_table => $has_table);
            }
            
            # Properties which are implied and have no additional information are skipped.
            next if @fields == 0;
            
            my $line = "        "
                . $name . (" " x ($max_name_length - length($name)))
                . " => { "
                . join(", ", @fields)
                . " },\n";
    
            $properties_src .= $line;
            $properties_printed{$name} = 1;
        }
        
        if (length($properties_src)) {            
            $perl .= "    $group => [\n" . $properties_src . "    ],\n";
        }
    }

    if (my @unique_constraint_props = sort { $a->unique_group cmp $b->unique_group } UR::Object::Property::Unique->get(class_name => $self->class_name)) {
        my %unique_groups;
        for my $uc_prop (@unique_constraint_props) {
            $unique_groups{$uc_prop->unique_group} ||= [];
            push @{ $unique_groups{$uc_prop->unique_group} }, $uc_prop;
        }

        $perl .= "    unique_constraints => [\n";
        for my $unique_group (values %unique_groups) {
            my @property_objects = map { 
                    UR::Object::Property->get(class_name => $self->class_name, property_name => $_->property_name); 
                } @$unique_group;
            #my @property_names = sort map { $_->property_name } @property_objects;
            my @property_names = sort map { $_->property_name } @$unique_group; 
            $perl .= "        { "
                . "properties => [qw/@property_names/], "
                . "sql => '" . $unique_group->[0]->unique_group . "'"
                . " },\n";
        }
        $perl .= "    ],\n";
    }

    $perl .= "    schema_name => '" . $self->schema_name . "',\n" if $self->schema_name;
    $perl .= "    data_source => '" . $self->data_source . "',\n" if $self->data_source;

    my $doc = $self->doc;
    if (defined($doc)) {
        $doc = Dumper($doc);
        $doc =~ s/\$VAR1 = //;
        $doc =~ s/;\s*$//;
    }
    #$perl .= "    source => '" . $self->source . "',\n" if defined $self->source;
    $perl .= "    doc => $doc,\n" if defined($doc);

=cut

    do {
        no warnings;
        
        my $new_desc = eval "{ $perl }";
        die $@ if $@;        
        
        my $old_desc = $self; #UR::Util::deep_copy($self);
        for my $key (keys %$old_desc) {            
            delete $old_desc->{$key} if $key =~ /^_/;            
        }
        for my $has (keys %{ $old_desc->{has} }) {
            my $p = $old_desc->{has}{$has};
            if ($p->{implied_by}) {
                delete $old_desc->{has}{$has};
            }
        }
        delete $old_desc->{db_committed};
        delete $old_desc->{id};
        delete $old_desc->{module_header_positions};
        delete $old_desc->{meta_class_name};        
        
        my $new_normalized = __PACKAGE__->_normalize_class_description(class_name => $class_name, %$new_desc);
        my $old_normalized = __PACKAGE__->_normalize_class_description(%$old_desc);
        my $old_src = Data::Dumper::Dumper($self);
        my $new_src = Data::Dumper::Dumper($new_normalized);
        unless ($old_src eq $new_src) {
            warn "source for $class_name does not normalize back to the original class!\n";
            print IO::File->new(">/tmp/old.pm")->print($old_src);
            print IO::File->new(">/tmp/new.pm")->print($new_src);        
        }
    };

=cut

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

sub _get_display_fields_for_property {
    my $self = shift;
    my $property = shift;
    my %params = @_;
    
    if(not $property->is_specified_in_module_header) {
        # we omit showing implied properties which have no additional data, unless they have their own docs, a specified column, etc.
        return();
    }    
    
    my @fields;    
    my $property_name = $property->property_name;
    
    my $type = $property->data_type;
    push @fields, "is => '$type'" if $type;
    
    if (defined($property->data_length) and length($property->data_length)) {
        push @fields, "len => " . $property->data_length
    }
    
    # show defined values
    for my $std_field_name (qw//) {
        my $property_name = "is_" . $std_field_name;
        push @fields, "$property_name => " . $property->$property_name if defined $property->$property_name;
    }

    # show only true values, false is default
    for my $std_field_name (qw/optional transient constant class_wide/) {
        my $property_name = "is_" . $std_field_name;
        push @fields, "$property_name => " . $property->$property_name if $property->$property_name;
    }

    #$line .= "references => '???', ";
    if ($property->is_legacy_eav) { 
        # temp hack for entity attribute values
        #push @fields, "delegate => { via => 'eav_" . $property->property_name . "', to => 'value' }";
        push @fields, "is_legacy_eav => 1";                
    }
    elsif ($property->is_delegated) {
        # do nothing
    }
    elsif ($property->is_calculated) {
        # do nothing
    }
    elsif ($property->is_transient) {
        # do nothing
    }
    elsif ($params{has_table}) {
        unless ($property->column_name) {
            die("no column for property on class with table: " . $property->property_name . " class: " . $self->class_name . "?");
        }
        if (uc($property->column_name) ne uc($property->property_name)) {
            push @fields,  "column_name => '" . $property->column_name . "'";
        }
    }
    
    my $implied_property = 0;
    if (defined($property->implied_by) and length($property->implied_by)) { 
        push @fields,  "implied_by => '" . $property->implied_by . "'";
        $implied_property = 1;
    }

    my $next_line_prefix = "\n" . (" " x 50);
    my $deep_indent_prefix = "\n" . (" " x 55);

    if (my @id_by = $property->id_by_property_links) {
        #push @fields, $next_line_prefix 
        #    . "id_by => [ "
        #    . join("\n$deep_indent_prefix", map { "'" . $_->property_name . "'" } @id_by )
        #    . " ]";
        push @fields, "id_by => " 
            . (@id_by > 1 ? '[ ' : '')
            . join(", ", map { "'" . $_->property_name . "'" } @id_by)
            . (@id_by > 1 ? ' ]' : '') 
    }

    if ($property->constraint_name) {
        push @fields, "constraint_name => '" . $property->constraint_name . "'";
    }
    
    my $desc = $property->description;
    if ($desc && length($desc)) {
        $desc =~ s/([\$\@\%\\\"])/\\$1/g;
        $desc =~ s/\n/\\n/g;
        push @fields,  $next_line_prefix . 'doc => "' . $desc . '"';
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
    my $namespace = $base_name;
    $namespace =~ s/\/.*$//;
    $namespace .= ".pm";
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

sub singleton_cache_dir {
    my $self = shift;
    my $singleton_cache_dir = $self->singleton_path;
    $singleton_cache_dir =~ s/\.pm$//;
    $singleton_cache_dir .= "/";
    return $singleton_cache_dir;
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

if ($package->isa("UR::Object::Type")) {
    print Carp::longmess($package);
}

    $DB::single = 1;

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

1;
