package UR::Namespace::Command::Base;
use strict;
use warnings;
use UR;

use Cwd;
use Carp;
use File::Find;

our $VERSION = "0.30"; # UR $VERSION;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'Command::V1',
    is_abstract => 1,
    has_transient => [ 
        namespace_name      =>  {   type => 'String',
                                    is_optional => 1,
                                    doc => 'Name of the Namespace to work in. Auto-detected if within a Namespace directory'
                                },
        lib_path            =>  {   type => "FilesystemPath",
                                    doc => "The directory in which the namespace module resides.  Auto-detected normally.",
                                    is_constant => 1,
                                    calculate_from => ['namespace_name'],
                                    calculate => q( # the namespace module should have gotten loaded in create()
                                                    my $namespace_module = $namespace_name;
                                                    $namespace_module =~ s#::#/#g;
                                                    my $namespace_path = Cwd::abs_path($INC{$namespace_module . ".pm"});
                                                    unless ($namespace_path) {
                                                        Carp::croak("Namespace module $namespace_name has not been loaded yet");
                                                    }
                                                    $namespace_path =~ s/\/[^\/]+.pm$//;
                                                    return $namespace_path;
                                                  ),
                                },
        working_subdir      =>  {   type => "FilesystemPath", 
                                    doc => 'The current working directory relative to lib_path',
                                    calculate => q( my $lib_path = $self->lib_path;
                                                    return UR::Util::path_relative_to($lib_path, Cwd::abs_path(Cwd::getcwd));
                                                  ),
                                },
        namespace_path      =>  { type => 'FilesystemPath',
                                  doc  => "The directory under which all the namespace's modules reside",
                                  is_constant => 1,
                                  calculate_from => ['namespace_name'],
                                  calculate => q(  my $lib_path = $self->lib_path;
                                                   return $lib_path . '/' . $namespace_name;
                                                ),
                                },
        verbose             =>  { type => "Boolean", is_optional => 1,
                                    doc => "Causes the command to show more detailed output."
                                },
    ],
    doc => 'a command which operates on classes/modules in a UR namespace directory'
);

sub create {
    my $class = shift;
    
    my ($rule,%extra) = $class->define_boolexpr(@_);
    my $namespace_name;
    if ($rule->specifies_value_for('namespace_name')) {
        $namespace_name = $rule->value_for('namespace_name');

    } else {
        $namespace_name = $class->resolve_namespace_name_from_cwd();
        unless ($namespace_name) {
            $class->error_message("Could not determine namespace name.");
            $class->error_message("Run this command from within a namespace subdirectory or use the --namespace-name command line option");
            return;
        }
        $rule = $rule->add_filter(namespace_name => $namespace_name);
    }

    # Use the namespace.
    $class->status_message("Loading namespace module $namespace_name") if ($rule->value_for('verbose'));
    eval "use above '$namespace_name';";
    if ($@) {
        $class->error_message("Error using namespace module '$namespace_name': $@");
        return;
    }

    my $self = $class->SUPER::create($rule);
    return unless $self;

    unless (eval { UR::Namespace->get($namespace_name) }) {
        $self->error_message("Namespace '$namespace_name' was not found");
        return;
    }

    if ($namespace_name->can("_set_context_for_schema_updates")) {
        $namespace_name->_set_context_for_schema_updates();
    }

    return $self;
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

sub resolve_namespace_name_from_cwd {
    my $class = shift;
    my $cwd = shift;
    $cwd ||= cwd();

    my @lib = grep { length($_) } split(/\//,$cwd);

    SUBDIR:
    while (@lib) {
        my $namespace_name = pop @lib;

        my $lib_path = "/" . join("/",@lib);
        my $namespace_module_path = $lib_path . '/' . $namespace_name . '.pm';
        if (-e $namespace_module_path) {
            my $fh = IO::File->new($namespace_module_path);
            next unless $fh;
            while (my $line = $fh->getline) {
                if ($line =~ m/package\s+$namespace_name\s*;/) {
                    # At this point $namespace_name should be a plain word with no ':'s
                    # and if the file sets the package to a single word with no colons,
                    # it's pretty likely that it's a # namespace module.
                    return $namespace_name;
                }
            }
        }
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

