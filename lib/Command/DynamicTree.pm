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
    my $subclass = shift;
    my $meta = $subclass->__meta__;
    if (grep { $_ eq __PACKAGE__ } $meta->parent_class_names) {
        my $delegating_class_name = $subclass;
        eval "sub ${subclass}::_delegating_class_name { '$delegating_class_name' }";
    }

    return 1;
}

sub _build_sub_command_mapping {
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
    for my $target_path (@target_paths) { 
        my $target = $target_path;
        $target =~ s#$base_path\/$ref_path/##; 
        $target =~ s/\.pm//;

        my $target_class_name = $ref_class . '::' . $target;  

        my $target_meta = UR::Object::Type->get($target_class_name);
        next unless $target_meta; 
        next unless $target_class_name->isa($ref_class); 

        push @target_class_names, $target => $target_class_name; 
    }
    my %target_classes = @target_class_names;

    my $mapping;
    for my $target (sort keys %target_classes) {
        my $target_class_name = $target_classes{$target};

        my $class_name = $delegating_class_name . '::' . $target; 

        my $module_name = $class_name;
        $module_name =~ s|::|/|g;
        $module_name .= '.pm';

        if (my @matches = grep { -e $_ . '/' . $module_name } @INC) {
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

# Sub commands that are themselves trees should use Command::Tree methods,
# otherwise should use Command::V2 methods
for my $method (
    qw/
        resolve_class_and_params_for_argv
        help_brief
        doc_help
        doc_manual
        resolve_option_completion_spec
        sorted_sub_command_classes
        sorted_sub_command_names
        sub_commands_table
        _categorize_sub_commands
        help_sub_commands
        doc_sub_commands
        sub_command_classes
        is_sub_command_delegator
        sub_command_names
        class_for_sub_command
        sub_command_dirs
    /
) {

    my $code = sub {
        my $self = shift;
        if ($self->_target_class_name) {
            # sub-command
            my $method1 = 'Command::V2::' . $method;
            return $self->$method1(@_);
        }
        else {
            # tree 
            my $method2 = 'SUPER::' . $method;
            return $self->$method2(@_)
        }
    };

    no strict;
    no warnings;
    *{$method} = $code;
}

1;

