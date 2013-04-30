package UR::Namespace::Command::Sys::ClassBrowser;

# This turns on the perl stuff to insert data in the DB
# namespace so we can get line numbers and stuff about
# loaded modules
#BEGIN {
#   unless ($^P) {
#       no strict 'refs';
#       *DB::DB = sub {};
#       $^P = 0x31f;
#   }
#}

use strict;
use warnings;
use UR;
use Data::Dumper;
use File::Spec;
use File::Basename;
use IO::File;
use Template;
use Plack::Request;
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
        $inh_inserter->($data);
    }
    1;
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
        my $data = shift;
        my $class_name = $data->{name};

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
            $by_class_name->{$parent_class} ||= $self->_class_name_cache_data_for_class_name($parent_class);
            my $parent_class_data = $by_class_name->{$parent_class};
            my $parent_class_tree = $do_insert->($parent_class_data);
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

print "In new execute!!\n";
$DB::single=1;
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
    return [ 500, [ 'Content-Type' => 'text/plain' ], [ 'Template failed', $tmpl->error ]];
}

sub _fourohfour {
    return [ 404, [ 'Content-Type' => 'text/plain' ], ['Not Found']];
}


sub detail_for_class {
    my $self = shift;
    my $env = shift;
    my $class = shift;

    my $class_meta = eval { $class->__meta__};
    unless ($class_meta) {
        return $self->_fourohfour;
    }
    return $self->_process_template('class-detail.html', { meta => $class_meta });
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

