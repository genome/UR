package Command::DynamicTree;

use strict;
use warnings;
use UR;

class Command::DynamicTree {
    is => 'Command::Tree',
    is_abstract => 1,
    doc => 'Base class for commands that delegate to sub-commands that may need to be dynamically created',
};

sub _init_subclass {
    $DB::single = 1;
    my $subclass = shift;
    my $meta = $subclass->__meta__;
    if (grep { $_ eq __PACKAGE__ } $meta->parent_class_names) {
        my $delegating_class_name = $subclass;
        eval "sub ${subclass}::_delegating_class_name { '$delegating_class_name' }";
    }

    return 1;
}

sub sub_command_dirs {
    $DB::single = 1;
    my $class = ref($_[0]) || $_[0];
    return ( $class eq $class->_delegating_class_name ? 1 : 0 );
}

sub _build_sub_command_mapping {
    $DB::single = 1;
    my ($class) = @_;

    unless ($class->can('_sub_commands_from')) {
        die "Class $class does not implement _sub_commands_from()!\n"
            . "This method should return the namespace to use a reference "
            . "for defining sub-commands."
    }
    my $ref_class = $class->_sub_commands_from;

    my $delegating_class_name = $class;

    my $module = $ref_class;
    $module =~ s/::/\//g;
    $module .= '.pm';
    my $base_path = $INC{$module};
    unless ($base_path) {
        if (UR::Object::Type->get($ref_class)) {
            $base_path = $INC{$module};
        }
        unless ($base_path) {
           die "Failed to find the path for ref class $ref_class!"; 
        }
    }
    $base_path =~ s/$module//;

    my $ref_path = $ref_class;
    $ref_path =~ s/::/\//g;

    my $full_ref_path = $base_path . '/' . $ref_path;

    my @target_paths = glob("$full_ref_path/*.pm");

    my @target_class_names;
    # All modules found under the reference class (Genome::ProcessingProfile)
    for my $target_path (@target_paths) { 
        my $target = $target_path;
        # Getting the last level of the package (ie, AmpliconAssembly)
        $target =~ s#$base_path\/$ref_path/##; 
        $target =~ s/\.pm//;

        # Full package name of reference package (ie, Genome::ProcessingProfile::AmpliconAssembly)
        my $target_class_name = $ref_class . '::' . $target;  

        # Skip the class if it doesn't exist or if it isn't a subclass of the given reference class
        # So, if it doesn't exist under Genome::ProcessingProfile or isn't a subclass of Genome::ProcessingProfile
        my $target_meta = UR::Object::Type->get($target_class_name);
        next unless $target_meta; 
        next unless $target_class_name->isa($ref_class); 

        # Mapping last level of package name to full path name
        # ie, AmpliconAssembly => Genome::ProcessingProfile::AmpliconAssembly
        push @target_class_names, $target => $target_class_name; 
    }
    my %target_classes = @target_class_names;

    # Needs to map the command name (amplicon-assembly) with the full class name we want (ie, Genome::Model::AmpliconAssembly)
    my $mapping;
    for my $target (sort keys %target_classes) {
        my $target_class_name = $target_classes{$target};

        # Full package name of class we need to find or create (ie, Genome::Model::AmpliconAssembly)
        my $class_name = $delegating_class_name . '::' . $target; 

        # Create file path pointing to module (ie, Genome/Model/AmpliconAssembly.pm)
        my $module_name = $class_name;
        $module_name =~ s|::|/|g;
        $module_name .= '.pm';

        $DB::single = 1;
        # If the module already exists...
        if (my @matches = grep { -e $_ . '/' . $module_name } @INC) {
            # Load the class
            my $c = UR::Object::Type->get($class_name);
            no warnings 'redefine';
            eval "sub ${class_name}::_target_class_name { '$target_class_name' }";
            use warnings;

            my $name = $class->_command_name_for_class_word($target);
            $mapping->{$name} = $class_name;
            next;
        }

        my @new_class_names = $class->_build_sub_command($class_name,$delegating_class_name,$target_class_name);
        for my $new_class_name (@new_class_names) {
            no warnings 'redefine';
            eval "sub ${new_class_name}::_target_class_name { '$target_class_name' }";
            use warnings;

            my $name = $class->_command_name_for_class_word($target);
            $mapping->{$name} = $class_name;
        }
    }

    return $mapping;
}

sub _build_sub_command {
    my ($self,$class_name,$delegating_class_name,$reference_class_name) = @_;
    class {$class_name} { 
        is => $delegating_class_name, 
        doc => '',
    };
    return $class_name;
}

sub _target_class_name { undef }

1;

