package UR::Namespace;

use strict;
use warnings;
use File::Find;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Namespace',
    is => ['UR::Singleton'],
    english_name => 'universal reflective namespace',
    is_abstract => 1,
    properties => [
        domain                           => { type => '', len => undef },
    ],
);

sub get_member_class {
    my $self = shift;
    return UR::Object::Type->get(@_);
}

sub get_default_context
{
    my $self = shift;
    my @contexts = $self->get_base_contexts;
    if (@contexts == 0) {
        return "UR::Context::DefaultBase";
    }
    elsif (@contexts == 1) {
        return $contexts[0];
    }
    else {
        Carp::confess("Namespace $self has multiple contexts, and does not override get_default_context() to specify a default!");
    }
}


sub get_default_data_source
{
    my $self = shift;
    my $context = $self->get_default_context;
    return $context->get_default_data_source;
}

# FIXME  These should change to using the namespace metadata DB when
# that's in place, rather than trolling through the directory tree
sub get_material_classes
{
    my $self = shift->_singleton_object;
    my @classes;
    if (my $cached = $self->{material_classes}) {
        @classes = map { UR::Object::Type->get($_) } @$cached;
    }
    else {
        my @names;
        for my $class_name ($self->_get_class_names_under_dir()) {
            my $class = eval { UR::Object::Type->get($class_name) };
            next unless $class;
            push @classes, $class;
            push @names, $class_name;
        }
        $self->{material_classes} = \@names;
    }
    return @classes;
}

sub get_material_class_names
{
    return map {$_->class_name} $_[0]->get_material_classes();
}

sub get_data_sources
{
    my $class = shift;
    if ($class eq 'UR' or (ref($class) and $class->id eq 'UR')) {
        return 'UR::DataSource::Meta';  # UR only has 1 "real" data source, the other stuff in that dir are base classes
    } else {
        return $class->_get_class_names_under_dir("DataSource");
    }
}

sub get_base_contexts
{
    return shift->_get_class_names_under_dir("Context");
}

sub get_vocabulary
{
    my $class = shift->_singleton_class_name;
    return $class . "::Vocabulary";
}

sub get_base_directory_name
{
    my $class = shift->_singleton_class_name;
    my $dir = $class->get_class_object->module_path;
    $dir =~ s/\.pm$//;
    return $dir;
}

sub get_deleted_module_directory_name
{
    my $self = shift;
    my $meta = $self->get_class_object;
    my $path = $meta->module_path;
    $path =~ s/.pm$//g;
    $path .= "/.deleted";
    return $path;
}

# FIXME This is misnamed...
# It really returns all the package names under the specified directory
# (assumming the packages defined in the found files are named like the
# pathname of the file), not just those that implement classes
sub _get_class_names_under_dir
{
    my $class = shift->_singleton_class_name;
    my $subdir = shift;

    Carp::confess if ref($class);

    my $dir = $class->get_base_directory_name;

    my $from;
    if (defined($subdir) and length($subdir)) {
        $from = join("/",$dir, $subdir);
    }
    else {
        $from = $dir;
    }

    my $namespace = $class;
    my @class_names;
    my $preprocess = sub {
        if ($File::Find::dir eq 't') {
            return();
        }
        elsif (-e ($File::Find::dir . "/UR_IGNORE")) {
            return();
        }
        else {
            return @_
        }
    };  
    my $wanted = sub {
        return if -d $File::Find::name;
        return if $File::Find::name =~ /\/\.deleted\//;
        return if -d $File::Find::name and -e $File::Find::name . '/UR_IGNORE';
        my $class = $File::Find::name;
        return unless $class =~ s/\.pm$//;
        $class =~ s/^$dir\//$namespace\//;
        return if $class =~ m([^\w/]);  # Skip names that make for illegal package names.  Must be word chars or a /
        $class =~ s/\//::/g;
        push @class_names, $class if $class;
    };
    find({ wanted => $wanted, preprocess => $preprocess },$from);
    return sort @class_names;
}

1;

