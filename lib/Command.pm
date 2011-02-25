package Command;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is_abstract => 1,
    subclass_description_preprocessor => '_resolve_version',
);

sub _resolve_version {
    my ($class, $classdef) = @_;
    return $classdef if $class =~ /::Ghost/;

    unless ($classdef->{class_name} =~ /^${class}::V\d+/) {
        my @base_classes = map { ref($_) ? @$_ : $_ } $classdef->{is};
        for my $base_class (@base_classes) {
            if ($base_class eq $class) {
                my $ns = $base_class;
                $ns =~ s/::.*//;
                my $version;
                if ($ns and $ns->can("component_version")) {
                    $version = $ns->component_version($class);
                }
                unless ($version) {
                    $version = '1';
                }
                $base_class = $class . '::V' . $version;
                eval "use $base_class";
                Carp::confess("Error using versiond module $base_class!:\n$@") if $@;
            }
        }
        $classdef->{is} = \@base_classes;
    }
    return $classdef;
}

1;
