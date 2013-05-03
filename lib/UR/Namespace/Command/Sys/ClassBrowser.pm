package UR::Namespace::Command::Sys::ClassBrowser;

# This turns on the perl stuff to insert data in the DB
# namespace so we can get line numbers and stuff about
# loaded modules
BEGIN {
   unless ($^P) {
       no strict 'refs';
       *DB::DB = sub {};
       $^P = 0x31f;
   }
}

use strict;
use warnings;
use UR;
use Data::Dumper;
use File::Spec;
use File::Basename;
use IO::File;
use Template;
use Plack::Request;
use Class::Inspector;

our $VERSION = "0.41"; # UR $VERSION;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command::Base',
    has_optional => [
        generate_cache  => { is => 'Boolean', default_value => 0, doc => 'Generate the class cache file' },
        use_cache       => { is => 'Boolean', default_value => 1, doc => 'Use the class cache instead of scanning for modules'},
        port            => { is => 'Integer', default_value => 8080, doc => 'TCP port to listen for connections' },
        timeout         => { is => 'Integer', doc => 'If specified, exit after this many minutes of inactivity' },
    ],
);

sub is_sub_command_delegator { 0;}

sub help_brief {
    "Start a web server to browse through the class and database structures.";
}

sub _class_info_cache_file_name_for_namespace {
    my($self, $namespace) = @_;
    unless ($INC{$namespace.'.pm'}) {
        eval "use $namespace";
        die $@ if $@;
    }
    my $class_cache_file = sprintf('.%s-class-browser-cache', $namespace);
    return File::Spec->catfile($namespace->get_base_directory_name, $class_cache_file);
}


sub load_class_info_for_namespace {
    my($self, $namespace) = @_;

    my $class_cache_file = $self->_class_info_cache_file_name_for_namespace($namespace);
    if ($self->use_cache and -f $class_cache_file) {
        $self->_load_class_info_from_cache_file($class_cache_file);
    } else {
        $self->status_message("Preloading class information for namespace $namespace...");
        $self->_load_class_info_from_modules_on_filesystem($namespace);
    }
}

sub _load_class_info_from_modules_on_filesystem {
    my $self = shift;
    my $namespace = shift;

    my $by_class_name = $self->{_cache}->{$namespace}->{by_class_name} ||= $self->_generate_class_name_cache($namespace);

    my $by_class_name_tree = $self->{_cache}->{$namespace}->{by_class_name_tree}
                            ||= UR::Namespace::Command::Sys::ClassBrowser::TreeItem->new(
                                name => $namespace,
                                relpath => $namespace.'.pm');
    my $by_class_inh_tree = $self->{_cache}->{$namespace}->{by_class_inh_tree}
                            ||= UR::Namespace::Command::Sys::ClassBrowser::TreeItem->new(
                                name => 'UR::Object',
                                relpath => 'UR::Object');
    my $by_directory_tree = $self->{_cache}->{$namespace}->{by_directory_tree}
                            ||= UR::Namespace::Command::Sys::ClassBrowser::TreeItem->new(
                                name => $namespace,
                                relpath => $namespace.'.pm' );
    my $inh_inserter = $self->_class_inheritance_cache_inserter($by_class_name, $by_class_inh_tree);
    foreach my $data ( values %$by_class_name ) {
        $self->_insert_cache_for_class_name_tree($data, $by_class_name_tree);
        $self->_insert_cache_for_path($data, $by_directory_tree);
        $inh_inserter->($data->{name});
    }
    1;
}


sub _cached_data_for_class {
    my($self, $class_name) = @_;

    my($namespace) = $class_name =~ m/^(\w+)(::)?/;
    return $self->{_cache}->{$namespace}->{by_class_name}->{$class_name};
}

# 1-level hash.  Maps a class name to a hashref containing simple
# data about that class.  relpath is relative to the namespace's module_path
sub _generate_class_name_cache {
    my($self, $namespace) = @_;

    my $cwd = Cwd::getcwd . '/';
    my $namespace_meta = $namespace->__meta__;
    my $namespace_dir = $namespace_meta->module_directory;
    (my $path = $namespace_meta->module_path) =~ s/^$cwd//;
    my $by_class_name = {  $namespace => {
                                name  => $namespace,
                                is    => $namespace_meta->is,
                                relpath  => $namespace . '.pm',
                                id  => $path,
                                file => File::Basename::basename($path),
                            }
                        };
    foreach my $class_meta ( $namespace->get_material_classes ) {
        my $class_name = $class_meta->class_name;
        $by_class_name->{$class_name} = $self->_class_name_cache_data_for_class_name($class_name);
    }
    return $by_class_name;
}

sub _class_name_cache_data_for_class_name {
    my($self, $class_name) = @_;

    my $class_meta = $class_name->__meta__;
    unless ($class_meta) {
        Carp::carp("Can't get class metadata for $class_name... skipping.");
        return;
    }
    my $namespace_dir = $class_meta->namespace->__meta__->module_directory;
    my $module_path = $class_meta->module_path;
    (my $relpath = $module_path) =~ s/^$namespace_dir//;
    return {
        name    => $class_meta->class_name,
        relpath => $relpath,
        path    => $module_path,
        file    => File::Basename::basename($relpath),
        is      => $class_meta->is,
    };
}

# Build the by-class-name tree data
sub _insert_cache_for_class_name_tree {
    my($self, $data, $tree) = @_;

    my @names = split('::', $data->{name});
    my $relpath = shift @names;  # Namespace is first part of the name
    while(my $name = shift @names) {
        $relpath = join('::', $relpath, $name);
        $tree = $tree->get_child($name)
                    || $tree->add_child(
                        name        => $name,
                        relpath     => $relpath);
    }
    $tree->data($data);
    return $tree;
}

# Build the by_directory_tree data
sub _insert_cache_for_path {
    my($self, $data, $tree) = @_;

    # split up the path to the module relative to the namespace directory
    my @path_parts = File::Spec->splitdir($data->{relpath});
    shift @path_parts if $path_parts[0] eq '.';  # remove . at the start of the path

    my $partial_path = shift @path_parts;
    while (my $subdir = shift @path_parts) {
        $partial_path = join('/', $partial_path, $subdir);
        $tree = $tree->get_child($subdir)
                    || $tree->add_child(
                            name    => $subdir,
                            relpath => $partial_path);
    }
    $tree->data($data);
    return $tree;
}


# build the by_class_inh_tree data
sub _class_inheritance_cache_inserter {
    my($self, $by_class_name, $tree) = @_;

    my $cache = $tree ? { $tree->name => $tree } : {};

    my $do_insert;
    $do_insert = sub {
        my $class_name = shift;
                                                  # FIXME isn't this a dup of a method I just added?!?
        $by_class_name->{$class_name} ||= $self->_class_name_cache_data_for_class_name($class_name);
        my $data = $by_class_name->{$class_name};

        if ($cache->{$class_name}) {
            return $cache->{$class_name};
        }
        my $node = UR::Namespace::Command::Sys::ClassBrowser::TreeItem->new(
                    name => $class_name, data => $data
                );
        $cache->{$class_name} = $node;

        if ((! $data->{is}) || (! @{ $data->{is}} )) {
            # no parents?!  This _is_ the root!
            return $tree = $node;
        }
        foreach my $parent_class ( @{ $data->{is}} ) {
            my $parent_class_tree = $do_insert->($parent_class);
            unless ($parent_class_tree->has_child($class_name)) {
                $parent_class_tree->add_child( $node );
            }
        }
        return $node;
    };

    return $do_insert;
}

sub _write_class_info_to_cache_file {
    my $self = shift;

    my $current_namespace = $self->namespace_name;
    return unless ($self->{_cache}->{$current_namespace});

    my $cache_file = $self->_class_info_cache_file_name_for_namespace($current_namespace);
    my $fh = IO::File->new($cache_file, 'w') || die "Can't open $cache_file for writing: $!";

    $fh->print( Data::Dumper->Dump([$self->{_cache}->{$current_namespace}]) );
    $fh->close();
    $self->status_message("Saved class info to cache file $cache_file");
}


sub execute {
    my $self = shift;

    if ($self->generate_cache) {
        $self->_load_class_info_from_modules_on_filesystem($self->namespace_name);
        $self->_write_class_info_to_cache_file();
        return 1;
    }

    $self->load_class_info_for_namespace($self->namespace_name);

    my $tt = $self->{_tt} ||= Template->new({ INCLUDE_PATH => $self->_template_dir, RECURSION => 1 });

    my $server = UR::Service::WebServer->create(timeout => $self->timeout, port => $self->port);

    my $router = UR::Service::UrlRouter->create( verbose => 1);
    my $assets_dir = $self->__meta__->module_data_subdirectory.'/assets/';
    $router->GET(qr(/assets/(.*)), $server->file_handler_for_directory( $assets_dir, 1));
    $router->GET('/', sub { $self->index(@_) });
    $router->GET(qr(/detail-for-class/(.*)), sub { $self->detail_for_class(@_) });
    $router->GET(qr(/render-perl-module/(.*)), sub { $self->render_perl_module(@_) });
    $router->GET(qr(/property-metadata-list/(.*)/(\w+)), sub { $self->property_metadata_list(@_) });

    $server->cb($router);
    $server->run();

    return 1;
}

sub _template_dir {
    my $self = shift;
    return $self->__meta__->module_data_subdirectory();
}

sub index {
    my $self = shift;
    my $env = shift;

    my $req = Plack::Request->new($env);
    my $namespace = $req->param('namespace') || $self->namespace_name;

    my $data = {
        namespaces  => [ map { $_->id } UR::Namespace->is_loaded() ],
        classnames  => $self->{_cache}->{$namespace}->{by_class_name_tree},
        inheritance => $self->{_cache}->{$namespace}->{by_class_inh_tree},
        paths       => $self->{_cache}->{$namespace}->{by_directory_tree},
    };

    return $self->_process_template('class-browser.html', $data);
}

sub _process_template {
    my($self, $template_name, $template_data) = @_;

    my $out = '';
    my $tmpl = $self->{_tt};
    $tmpl->process($template_name, $template_data, \$out)
        and return [ 200, [ 'Content-Type' => 'text/html' ], [ $out ]];

    # Template error :(
    $self->error_message("Template failed: ".$tmpl->error);
    return [ 500, [ 'Content-Type' => 'text/plain' ], [ 'Template failed', $tmpl->error ]];
}

sub _fourohfour {
    return [ 404, [ 'Content-Type' => 'text/plain' ], ['Not Found']];
}

sub _line_for_function {
    my($self, $name) = @_;
    my $info = $DB::sub{$name};

    return () unless $info;
    my ($file,$start);
    if ($info =~ m/\[(.*?):(\d+)\]/) {  # This should match eval's and __ANON__s
        ($file,$start) = ($1,$2);

    } elsif ($info =~ m/(.*?):(\d+)-(\d+)$/) {
        ($file,$start) = ($1,$2);

    }

    if ($start) {
        # Convert $file into a package name
        foreach my $inc ( keys %INC ) {
            if ($INC{$inc} eq $file) {
                (my $pkg = $inc) =~ s/\//::/g;
                $pkg =~ s/\.pm$//;
                return (package => $pkg, line => $start);
            }
        }
    }
    return;
}

# Return a list of package names where $method is defined
sub _overrides_for_method {
    my($self, $class, $method) = @_;

    my %seen;
    my @results;
    my @isa = ($class);
    while (my $target_class = shift @isa) {
        next if $seen{$target_class}++;
        if (Class::Inspector->function_exists($target_class, $method)) {
            push @results, $target_class;
        }
        {   no strict 'vars';
            push @isa, eval '@' . $target_class . '::ISA';
        }
    }
    return \@results;
}

sub detail_for_class {
    my $self = shift;
    my $env = shift;
    my $class = shift;

    my $class_meta = eval { $class->__meta__};

    my $tree = UR::Namespace::Command::Sys::ClassBrowser::TreeItem->new(
                                name => 'UR::Object',
                                relpath => 'UR::Object');

    my $namespace = $class_meta->namespace;
    my $treebuilder = $self->_class_inheritance_cache_inserter(
                            $self->{_cache}->{$namespace}->{by_class_name},
                            $tree,
                    );
    $treebuilder->($class);

    unless ($class_meta) {
        return $self->_fourohfour;
    }

    my @public_methods = sort { $a->[2] cmp $b->[2] }  # sort by function name
                        @{ Class::Inspector->methods($class, 'public', 'expanded') };
    my @private_methods = sort { $a->[2] cmp $b->[2] }  # sort by function name
                        @{ Class::Inspector->methods($class, 'private', 'expanded') };

    # Convert each of them to a hashref for easier access
    foreach ( @public_methods, @private_methods ) {
        my $class = $_->[1];
        my $method = $_->[2];
        my $function = $_->[0];
        my $cache = $self->_cached_data_for_class($class);
        $_ = {
            class       => $class,
            method      => $method,
            file        => $cache->{relpath},
            overrides   => $self->_overrides_for_method($class, $method),
            $self->_line_for_function($function),
        };
    }

    my @sorted_properties = sort { $a->property_name cmp $b->property_name }
                            $class_meta->properties;

    my $tmpl_data = {
        meta                    => $class_meta,
        property_metas          => \@sorted_properties,
        class_inheritance_tree  => $tree,
        public_methods          => \@public_methods,
        private_methods         => \@private_methods,
    };
    return $self->_process_template('class-detail.html', $tmpl_data);
}

sub render_perl_module {
    my($self, $env, $module_name) = @_;

    my $module_path;
    if (my $class_meta = eval { $module_name->__meta__ }) {
        $module_path = $class_meta->module_path;

    } else {
        ($module_path = $module_name) =~ s/::/\//g;
        $module_path = $INC{$module_path.'.pm'};
    }
    unless ($module_path and -f $module_path) {
        return $self->_fourohfour;
    }

    my $fh = IO::File->new($module_path, 'r');
    my @lines = <$fh>;
    chomp(@lines);
    return $self->_process_template('render-perl-module.html', { module_name => $module_name, lines => \@lines });
}

# Render the popover content when hovering over a row in the
# class property table
sub property_metadata_list {
    my($self, $env, $class_name, $property_name) = @_;

    my $class_meta = $class_name->__meta__;
    unless ($class_meta) {
        return $self->_fourohfour;
    }
    my $prop_meta = $class_meta->property_meta_for_name($property_name);
    unless ($prop_meta) {
        return $self->_fourohfour;
    }

    return $self->_process_template('partials/property_metadata_list.html',
                    { meta => $prop_meta,
                      show => [qw(  doc class_name column_name data_type data_length is_id
                                    via to where reverse_as id_by
                                    valid_values example_values  is_optional is_transient is_constant
                                    is_mutable is_delegated is_abstract is_many is_deprecated
                                    is_calculated calculate_perl calculate_sql
                                )],
                    });
}


package UR::Namespace::Command::Sys::ClassBrowser::TreeItem;

our $ug = Data::UUID->new();
sub new {
    my $class = shift;
    my %node = @_;
    die "new() requires a 'name' parameter" unless (exists $node{name});

    $node{children} = {};
    $node{id} ||= $ug->create_str;
    my $self = bless \%node, __PACKAGE__;
    return $self;
}

sub id {
    return shift->{id};
}

sub name {
    return shift->{name};
}

sub relpath {
    return shift->{relpath};
}

sub data {
    my $self = shift;
    if (@_) {
        $self->{data} = shift;
    }
    return $self->{data};
}

sub has_children {
    my $self = shift;
    return %{$self->{children}};
}

sub children {
    my $self = shift;
    return [ values(%{$self->{children}}) ];
}

sub has_child {
    my $self = shift;
    my $child_name = shift;
    return exists($self->{children}->{$child_name});
}

sub get_child {
    my $self = shift;
    my $child_name = shift;
    return $self->{children}->{$child_name};
}

sub add_child {
    my $self = shift;
    my $child = ref($_[0]) ? shift(@_) : $self->new(@_);
    $self->{children}->{ $child->name } = $child;
}


1;

