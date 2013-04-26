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

    my $by_class_name_tree = $self->{_cache}->{$namespace}->{by_class_name_tree} ||= {};
    my $by_class_inh_tree = $self->{_cache}->{$namespace}->{by_class_inh_tree} ||= {};
    my $by_directory_tree = $self->{_cache}->{$namespace}->{by_directory_tree} ||= {};
    foreach my $data ( values %$by_class_name ) {
        $self->_insert_cache_for_path($data, $by_directory_tree);
        #$self->_insert_cache_for_class_name_tree($data, $by_class_name_tree);
        #$self->_insert_cache_for_class_inh_tree($data, $by_class_name, $by_class_inh_tree);
    }
    1;
}

sub _generate_class_name_cache {
    my($self, $namespace) = @_;

    my $cwd = Cwd::getcwd;
    my $namespace_meta = $namespace->__meta__;
    (my $path = $namespace_meta->module_path) =~ s/^$cwd/\./;
    my $by_class_name = {  $namespace => {
                                __name  => $namespace,
                                __is    => $namespace_meta->is,
                                __path  => $path,
                                __file => File::Basename::basename($path),
                            }
                        };
    foreach my $class_meta ( $namespace->get_material_classes ) {

        my $class_name = $class_meta->class_name;
        ($path = $class_meta->module_path) =~ s/^$cwd/\./;
        $by_class_name->{$class_name} = {
            __name  => $class_name,
            __path  => $path,
            __file  => File::Basename::basename($path),
            __is    => $class_meta->is,
        };
    }
    return $by_class_name;
}


# Build the by_directory_tree data
sub _insert_cache_for_path {
    my($self, $data, $pathstruct) = @_;

    # split up the path to the module relative to the namespace directory
    my @currentpath = File::Spec->splitdir($data->{__path});
    shift @currentpath if $currentpath[0] eq '.';  # remove . at the start of the path

    my $currentpath;
    while (@currentpath > 1) {
        my $dir = shift @currentpath;
        $currentpath = defined($currentpath) ? join('/', $currentpath, $dir) : $dir;
        unless (exists $pathstruct->{$dir}) {
            $pathstruct->{$dir} = {
                __path      => $currentpath,
                __is_dir    => 1,
                __file      => $dir,
                __name      => $dir,
            };
        }
        $pathstruct = $pathstruct->{$dir};
    }
    $pathstruct->{ $currentpath[0] } = $data;
}

sub cache_info_for_pathname {
    my($self, $namespace, $pathname) = @_;
    die "class_info_for_pathname requires a \$namespace" unless defined $namespace;

    my $pathstruct = $self->{_cache}->{$namespace}->{by_directory_tree};
    if ($pathname) {
        my @paths = File::Spec->splitdir($pathname);
        while(my $dir = shift @paths) {
            next if $dir eq '.';
            last unless $pathstruct;
            $pathstruct = $pathstruct->{$dir};
        }
    }
    return $pathstruct;
}

# build the by_class_name_tree data
sub _insert_cache_for_class_name_tree {
    my($self, $data, $classstruct) = @_;

    my @names = split('::', $data->{class_name});

    while(@names > 1) {
        my $name = shift @names;
        $classstruct = $classstruct->{$name} ||= {};
    }
    $classstruct->{ $names[0] } = $data;
}

# build the by_class_inh_tree data
sub _insert_cache_for_class_inh_tree {
    my($self, $data, $by_class_name, $classtree, @inh) = @_;

    @inh = ( $data->{class_name} ) unless @inh;  # first (non-recursive) call?

    # find the parents of the last class added to the @inh list
    my $is_list = $by_class_name->{$inh[-1]}->{is};
    if ($is_list and @$is_list) {
        # This class has one or more parents
        $self->_insert_cache_for_class_inh_tree($data, $by_class_name, $classtree, @inh, $_) foreach @$is_list;

    } else {
        # At the root - no more parents
        while (@inh > 1) {
            my $name = pop @inh;
            $classtree = $classtree->{$name} ||= {};
        }
        $classtree->{ $inh[0] } = $data;
    }
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
        #classnames  => $self->{_cache}->{$namespace}->{by_class_name_tree},
        #inheritance => $self->{_cache}->{$namespace}->{by_class_inh_tree},
        paths       => $self->{_cache}->{$namespace}->{by_directory_tree},
        valid_paths => sub {
                            my $hash = shift;
                            return [ sort {$a cmp $b }
                                     grep { ! m/^__/ } keys %$hash ];
                        },
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

1;
