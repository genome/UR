use warnings;
use strict;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";

use UR;
use File::Temp;
use File::Slurp;
use Path::Class;
use List::MoreUtils;
use Sub::Install;
use Test::More tests => 1;

my %setup;
subtest 'setup' => sub{
    plan tests => 4;

    # Write commands structure
    my $tempdir = Path::Class::dir( File::Temp::tempdir(CLEANUP => 1) );
    my $cmd_file = $tempdir->file('UrtCommand.pm');
    File::Slurp::write_file($cmd_file, "package UrtCommand;\nclass UrtCommand { is => 'Command::Tree' }\n");
    my $subdir = $tempdir->subdir('UrtCommand');
    mkdir $subdir;
    my $subcmd_file = $subdir->file('Happy.pm');
    File::Slurp::write_file($subcmd_file, "package UrtCommand::Happy;\nclass UrtCommand::Happy { is => 'Command::Tree' }\n");

    # Old _build_sub_command_mapping method
    my $build_sub_command_mapping_without_quotemeta_closure = sub{
        my $class = shift;
        $class = ref($class) || $class;

        my @source_classes = $class->command_tree_source_classes;

        my $mapping;
        do {
            no strict 'refs';
            $mapping = ${ $class . '::SUB_COMMAND_MAPPING'};
            if (ref($mapping) eq 'HASH') {
                return $mapping;
            }
        };

        for my $source_class (@source_classes) {
            # check if this class is valid
            eval{ $source_class->class; };
            if ( $@ ) {
                warn $@;
            }

            # for My::Foo::Command::* commands and sub-trees
            my $subdir = $source_class;
            $subdir =~ s|::|\/|g;

            # for My::Foo::*::Command sub-trees
            my $source_class_above = $source_class;
            $source_class_above =~ s/::Command//;
            my $subdir2 = $source_class_above;
            $subdir2 =~ s|::|/|g;

            # check everywhere
            for my $lib (@INC) {
                my $subdir_full_path = $lib . '/' . $subdir;

                # find My::Foo::Command::*
                if (-d $subdir_full_path) {
                    my @files = glob("\Q${subdir_full_path}/*");
                    for my $file (@files) {
                        my $basename = basename($file);
                        $basename =~ s/.pm$// or next;
                        my $sub_command_class_name = $source_class . '::' . $basename;
                        my $sub_command_class_meta = UR::Object::Type->get($sub_command_class_name);
                        unless ($sub_command_class_meta) {
                            local $SIG{__DIE__};
                            local $SIG{__WARN__};
                            # until _use_safe is refactored to be permissive, use directly...
                            print ">> $sub_command_class_name\n";
                            eval "use $sub_command_class_name";
                        }
                        $sub_command_class_meta = UR::Object::Type->get($sub_command_class_name);
                        next unless $sub_command_class_name->isa("Command");
                        next if $sub_command_class_meta->is_abstract;
                        next if $sub_command_class_name eq $class;
                        my $name = $source_class->_command_name_for_class_word($basename);
                        $mapping->{$name} = $sub_command_class_name;
                    }
                }

                # find My::Foo::*::Command
                $subdir_full_path = $lib . '/' . $subdir2;
                my $pattern = $subdir_full_path . '/*/Command.pm';
                my @paths = glob("\Q$pattern\E");
                for my $file (@paths) {
                    next unless defined $file;
                    next unless length $file;
                    next unless -f $file;
                    my $last_word = File::Basename::basename($file);
                    $last_word =~ s/.pm$// or next;
                    my $dir = File::Basename::dirname($file);
                    my $second_to_last_word = File::Basename::basename($dir);
                    my $sub_command_class_name = $source_class_above . '::' . $second_to_last_word . '::' . $last_word;
                    next unless $sub_command_class_name->isa('Command');
                    next if $sub_command_class_name->__meta__->is_abstract;
                    next if $sub_command_class_name eq $class;
                    my $basename = $second_to_last_word;
                    $basename =~ s/.pm$//;
                    my $name = $source_class->_command_name_for_class_word($basename);
                    $mapping->{$name} = $sub_command_class_name;
                }
            }
        }
        return $mapping;
    };
    my $build_sub_command_mapping_with_quotemeta_closure = Command::Tree->can('_build_sub_command_mapping');

    # Add tempdir to INC
    push @INC, "$tempdir";

    # Use em to make sure they work
    use_ok('UrtCommand');
    use_ok('UrtCommand::Happy');

    # Get the correct mapping with the fixed code
    my $expected_mapping = { happy => 'UrtCommand::Happy', };
    my $mapping = UrtCommand->_build_sub_command_mapping;
    is_deeply($mapping, $expected_mapping, 'sub command mapping correct');

    # Reintall the old method, then get the incorrect (undef) mapping
    Sub::Install::reinstall_sub({
            code => $build_sub_command_mapping_without_quotemeta_closure,
            as => '_build_sub_command_mapping',
            into => 'Command::Tree',
        });
    $mapping = UrtCommand->_build_sub_command_mapping;
    is($mapping, undef, 'sub command mapping is not correct');

};

done_testing();
