package UR::Namespace::Command::Base;
use strict;
use warnings;
use UR;
use Cwd;

our $VERSION = "0.30"; # UR $VERSION;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'Command::V1',
    is_abstract => 1,
    has_transient => [ 
        lib_path            =>  {   type => "FilesystemPath", 
                                    is_optional => 1,
                                    doc => "The directory under which the namespace module resides.  Auto-detected normally."
                                },  
        namespace_subdir    =>  {   type => "FilesystemPath", 
                                    is_optional => 1,
                                    doc => "The sub-directory under the lib path for the namespace.  Auto-detected normally."
                                },
        working_subdir      =>  {   type => "FilesystemPath", 
                                    is_optional => 1,
                                    doc => "The sub-directory under the namespace subdir which is the pwd.  Auto-detected normally.",
                                },
        verbose             =>  { type => "Boolean", is_optional => 1,
                                    doc => "Causes the command to show more detailed output."
                                },
    ],
    doc => 'a command which operates on classes/modules in a UR namespace directory'
);

sub create {
    my $class = shift;
    
    my ($lib_path,$namespace_subdir,$working_subdir) =
        $class->resolve_lib_namespace_working_dirs();    
    if (!$lib_path and -e "UR.pm") {
        # TEMPORARY: For development of ur commands (bootstrapping...)
        $lib_path = cwd();
    }        
    
    #my ($rule,%extra) = $class->define_boolexpr(@_);    
    my ($rule,%extra) = UR::BoolExpr->resolve($class,@_);    
    
    return $class->SUPER::create(
        lib_path => $lib_path,
        namespace_subdir => $namespace_subdir,
        working_subdir => $working_subdir,
        $rule->params_list, 
        %extra
    );    
}

sub command_name {
    my $class = shift;
    return "ur" if $class eq __PACKAGE__;
    my $name = $class->SUPER::command_name;
    $name =~ s/^u-r namespace/ur/;
    return $name;
}

sub help_detail {
    return shift->help_brief
}

sub namespace_path {
    my $self = shift;
    my $lib_path = $self->lib_path;
    my $namespace_subdir = $self->namespace_subdir;
    return undef unless $namespace_subdir;
    return $lib_path . "/" . $namespace_subdir;
}

sub working_path {
    my $self = shift;
    my $namespace_path = $self->namespace_path;
    my $working_subdir = $self->working_subdir;
    return $namespace_path unless $working_subdir;
    return $namespace_path . "/" . $working_subdir;
}

sub namespace_name {
    my $self = shift;
    my $namespace_name = $self->namespace_subdir;
    return undef unless $namespace_name;
    $namespace_name =~ s/\//::/g;
    return $namespace_name;
}

sub _test_cases_in_tree {
    my $self = shift;
    my @test_cases;
    unless (@_) {
        my $lib_path = $self->lib_path;
        my $namespace_subdir = $self->namespace_subdir;
        unless ($namespace_subdir) {
            die 'This command must be run in the top level of a UR::Namespace directory.  Run "ur create MyNamespace".';
        }
        @test_cases =  (grep { /\.t$/ } `cd $lib_path; find $namespace_subdir/*`);
        chomp @test_cases;
    }
    else {
        # this method takes either module paths or class names as params
        # normalize to module paths
        my $working_path = $self->working_path;
        my $lib_path = $self->lib_path;
        my $subdir = join("/", grep { $_ } $self->namespace_subdir,$self->working_subdir);

        for my $name (@_) {
            my $full_name = join("/",$working_path,$name);
            my $lib_relative_name = join("/", $subdir, $name);
            if (-e $full_name) {
                if ($name =~ /\.t$/) {
                    push @test_cases, $lib_relative_name;
                }
                elsif (-d $name) {
                    my @more = (grep { /\.t$/ } `cd $lib_path; find $lib_relative_name`);
                    chomp @more;
                    for (@more) { s/\/\.\//\//g; s/\/[^\/]+\/\..\//\//g; }
                    push @test_cases, @more;
                }
                else {
                    next;
                }
            }
        }
    }
    return sort @test_cases;
}

sub _modules_in_tree {
    my $self = shift;
    my @modules;
    unless (@_) {
        my $lib_path = $self->lib_path;
        my $namespace_subdir = $self->namespace_subdir;
        unless ($namespace_subdir) {
            die 'This command must be run in the top level of a UR::Namespace directory.  Run "ur create MyNamespace".';
        }
        @modules =  ($namespace_subdir . ".pm", grep { /\.pm$/ } `cd $lib_path; find $namespace_subdir/*`);
        chomp @modules;
    }
    else {
        # this method takes either module paths or class names as params
        # normalize to module paths
        my $working_path = $self->working_path;
        my $lib_path = $self->lib_path;
        my $subdir = join("/", grep { $_ } $self->namespace_subdir,$self->working_subdir);

        for my $name (@_) {
            my $full_name = join("/",$working_path,$name);
            my $lib_relative_name = join("/", $subdir, $name);
            if (-e $full_name) {
                if ($name =~ /\.pm$/) {
                    push @modules, $lib_relative_name;
                }
                elsif (-d $name) {
                    my @more = (grep { /\.pm$/ } `cd $lib_path; find $lib_relative_name`);
                    chomp @more;
                    for (@more) { s/\/\.\//\//g; s/\/[^\/]+\/\..\//\//g; }
                    push @modules, @more;
                }
                else {
                    warn "$name: ignoring non-module...";
                    next;
                }
            }
            else {
                # see if we have a class name
                my $file_name = $name;
                $file_name =~ s/::/\//g;
                $file_name .= ".pm";
                unless (-e $lib_path . "/" . $file_name) {
                    warn "$name: no module file found, and no class found!";
                    next;
                }
                push @modules, $file_name;
            }
        }
    }
    return sort @modules;
}

sub _class_names_in_tree {
    my $self = shift;
    $self->_init;
    my @modules = $self->_modules_in_tree(@_);
    my @class_names;
    for my $module (@modules) {
        my $class = $module;
        $class =~ s/\//::/g;
        $class =~ s/\.pm$//;
        push @class_names, $class;
    }
    return @class_names;
}

sub _class_objects_in_tree {
    my $self = shift;
    $self->_init;
    my @class_names = $self->_class_names_in_tree(@_);
    my @class_objects;
    for my $class_name (sort { uc($a) cmp uc($b) } @class_names) {
        unless(UR::Object::Type->use_module_with_namespace_constraints($class_name)) {
        #if ($@) {
            print STDERR "Failed to use class $class_name!\n";
            print STDERR $@,"\n";
            next;
        }
        my $c = UR::Object::Type->is_loaded(class_name => $class_name);
        unless ($c) {
            #print STDERR "Failed to find class object for class $class_name\n";
            next;
        }
        push @class_objects, $c;
        #print $class_name,"\n";
    }
    return @class_objects;
}

sub resolve_class_and_params_for_argv {
    # This is used by execute_and_exit, but might be used within an application.
    my $self = shift;
    my ($delegate, $params) = $self->SUPER::resolve_class_and_params_for_argv(@_);
    
    if ($params and ($self eq $delegate)) {
        my ($lib_path,$namespace_subdir,$working_subdir) =
            $delegate->resolve_lib_namespace_working_dirs();
    
        if (!$lib_path and -e "UR.pm") {
            # TEMPORARY: For development of ur commands (bootstrapping...)
            $lib_path = cwd();
        }
    
        if ($lib_path) {
            # new: params
            $params->{lib_path}             = $lib_path;
            $params->{namespace_subdir}     = $namespace_subdir;
            $params->{working_subdir}       = $working_subdir;
        }
    }
    
    return $delegate, $params;
}


sub _init {
    my $self = shift;
    
    return if $self->{_init};

    my $namespace = $self->namespace_name;
    unless ($namespace) {
        $self->error_message("This command must be run from within a UR namespace directory.");
        return;
    }

    # Ensure the right modules are visible to the command.
    # Make the lib accessible.
    
    # We'd like to "use lib" this directory,
    # but any other -I/use-lib requests should still 
    # come ahead of it.  This requires a little munging.

    #print "INC @INC\n"; 
    my $lib_path        = $self->lib_path;
    my @used_libs = UR::Util->used_libs;
    for (@used_libs) {
        shift @INC;
    }
    @INC = (@used_libs, $lib_path, @INC);
    #print "INC @INC\n"; 

    # Use the namespace.
    eval "use $namespace;";
    if ($@) {
        $self->error_message("Error using namespace $namespace: $@");
        return;
    }

    unless (eval { UR::Namespace->get($namespace) }) { 
        $DB::single = 1;
        $self->error_message("No namespace '$namespace' found!");
        return;
    }

    if ($namespace->can("_set_context_for_schema_updates")) {
        $namespace->_set_context_for_schema_updates();
    }

    $self->{_init} = 1;
    return 1;
}

use Cwd;

sub resolve_lib_namespace_working_dirs {
    my $class = shift;
    my $cwd = shift;
    $cwd ||= cwd();

    my @path = grep { length($_) } split(/\//,$cwd);
    
    my @lib = grep { length($_) } split(/\//,$cwd);
    my @namespace_subdirs = pop @lib;
    my @working_subdirs;

    my $prefix = UR::Util->used_libs_perl5lib_prefix;
    while (@lib) {
        my $lib_path = "/" . join("/",@lib);
        my $namespace_subdir = join("/",@namespace_subdirs);
        my $working_subdir = join("/",@working_subdirs);

        my $namespace_path = join("/",$lib_path,$namespace_subdir);
        my $working_path = join("/",$namespace_path,$working_subdir);

        my $namespace_module_path = $namespace_path . ".pm";
        if (-e $namespace_module_path) {
            my $ns = $namespace_subdirs[-1];
            my $fh = IO::File->new($namespace_module_path);
            my $found = 0;
            while (my $line = $fh->getline) {
                if ($line =~ /package $ns\s*;/) {
                    $fh->close;
                    return ($lib_path, $namespace_subdir, $working_subdir);
                }
            }
            $fh->close;
        }
        unshift @working_subdirs, pop(@namespace_subdirs);
        unshift @namespace_subdirs, pop(@lib);
    }

    return;
}


1;


=pod

=head1 NAME

UR::Namespace::Command - Top-level Command module for the UR namespace commands

=head1 DESCRIPTION

This class is the parent class for all the namespace-manipluation command
modules, and the root for command handling behind the 'ur' command-line
script.  

There are several sub-commands for manipluating a namespace's metadata.

=over 4

=item browser 

Start a lightweight web server for viewing class and schema information

=item commit

Update data source schemas based on the current class structure

=item define

Define metadata instances such as classes, data sources or namespaces

=item describe

Get detailed information about a class

=item diff

Show a diff for various kinds of other ur commands.

=item info

Show brief information about class or schema metadata

=item list

List various types of things

=item redescribe

Outputs class description(s) formatted to the latest standard

=item rename

Rename logical schema elements.

=item rewrite

Rewrites class descriptions headers to normalize manual changes.

=item test

Sub-commands related to testing

=item update

Update metadata based on external data sources

=back

Some of these commands have sub-commands of their own.  You can get more
detailed information by typing 'ur <command> --help' at the command line.

=head1 SEE ALSO

Command, UR, UR::Namespace

=cut

