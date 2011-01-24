package UR::Namespace;

use strict;
use warnings;
use File::Find;

require UR;
our $VERSION = "0.29"; # UR $VERSION;

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

# Subclasses can override this method to tell the dynamic module loader 
# whether it should go ahead and load the given module name or not.
# The default behavior is to go ahead and try for them all
sub should_dynamically_load_class {
    # my($self,$class_name) = @_;
    return 1;
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
        #return $class->_get_class_names_under_dir("DataSource");
        my @ds_names = $class->_get_class_names_under_dir("DataSource");
        my @ds_objs = map { $_->get() } @ds_names;
        return @ds_objs;
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
    my $dir = $class->__meta__->module_path;
    $dir =~ s/\.pm$//;
    return $dir;
}

sub get_deleted_module_directory_name
{
    my $self = shift;
    my $meta = $self->__meta__;
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


=pod

=head1 NAME 

UR::Namespace - Manage collections of packages and classes

=head1 SYNOPSIS

In a file called MyApp.pm:

  use UR;
  UR::Object::Type->define(
      class_name => 'MyApp',
      is => 'UR::Namespace',
  );

Other programs, as well as modules in the MyApp subdirectory can now put

  use MyApp;

in their code, and they will have access to all the classes and data under
the MyApp tree.  

=head1 DESCRIPTION

A UR namespace is the top-level object that represents your data's class
structure in the most general way.  After use-ing a namespace module, the
program gets access to the module autoloader, which will automaticaly use
modules on your behalf if you attempt to interact with their packages in
a UR-y way, such as calling get().

Most programs will not interact with the Namespace, except to C<use> its
package.

=head1 Methods

=over 4

=item get_material_classes

  my @class_metas = $namespace->get_material_classes();

Return a list of L<UR::Object::Type> class metadata object that exist in
the given Namespace.  Note that this uses File::Find to find C<*.pm> files
under the Namespace directory and calls C<UR::Object::Type-E<gt>get($name)>
for each package name to get the autoloader to use the package.  It's likely
to be pretty slow.

=item get_material_class_names

  my @class_names = $namespace->get_material_class_names()

Return just the names of the classes produced by C<get_material_classes>.

=item get_data_sources

  my @data_sources = $namespace->get_data_sources()

Return the data source objects it finds defined under the DataSource
subdirectory of the namespace.

=item get_base_directory_name

  my $path = $namespace->get_base_directory_name()

Returns the directory path where the Namespace module was loaded from.

=back

=head1 SEE ALSO

L<UR::Object::Type>, L<UR::DataSource>, L<UR::Context>

=cut
