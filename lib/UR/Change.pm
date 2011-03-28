
package UR::Change;

use strict;
use warnings;

use IO::File;

require UR;
our $VERSION = "0.30"; # UR $VERSION;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    has => [  changed_class_name => { is => 'String' },
              changed_id         => { },
              changed_aspect     => { is => 'String' },
              undo_data          => { is_optional => 1 },   # Some changes (like create) have no undo data
           ],
    is_transactional => 1,
);

sub undo {
    my $self = shift;
    my $changed_class_name = $self->changed_class_name;
    my $changed_id = $self->changed_id;
    my $changed_aspect = $self->changed_aspect;
    my $undo_data = $self->undo_data;

    if (0) {
        no warnings;
        my @k = qw/changed_class_name changed_id changed_aspect undo_data/;
        my @v = @$self{@k};
        print "\tundoing @v\n";
    };

    # Ghosts are managed internally by create/delete.
    # Allow reversal of those methods to indirectly reverse ghost changes.
    if ($changed_class_name =~ /::Ghost/) {
        if ($changed_aspect !~ /^(create|delete)(_object|)$/) {
            Carp::confess("Unlogged change on ghost? @_");
        }
        return 1;
    }

    # For tracking "external" changes allow the undo to execute a closure
    if ($changed_aspect eq 'external_change') {
        if (ref($undo_data) eq 'CODE') {
            return eval { &$undo_data };
        }
        else {
            die $self->error_message("'external_change' expects a code ref for undo data!");
        }
    }

    my $changed_obj;
    if ($changed_aspect eq "delete" or $changed_aspect eq "unload") {
        $undo_data = '' unless defined $undo_data;
        $changed_obj = eval "no strict; no warnings; " . $undo_data;
        bless($changed_obj, 'UR::DeletedRef') if (ref $changed_obj); # changed class so that UR::Object::DESTROY is not called on a "fake" UR::Object
        if ($@) {
            Carp::confess("Error reconstructing $changed_aspect data for @_: $@");
        }
        return unless $changed_obj;
    }
    else {
        $changed_obj = $changed_class_name->get($changed_id);
    }
    # TODO: if no changed object, die?


    if ($changed_aspect eq "__define__") {
        UR::Object::unload($changed_obj);
    }
    elsif ($changed_aspect eq "create") {
        UR::Object::delete($changed_obj);
    }
    elsif ($changed_aspect eq "delete") {
        my %stored;
        for my $key (keys %$changed_obj) {
            if ($key =~ /^(status|warning|error|debug)_message$/
                or ref($changed_obj->{$key})
            ) {
                $stored{$key} = delete $changed_obj->{$key};
            }
        }
        $changed_obj = UR::Object::create($changed_class_name,%$changed_obj);
        for my $key (keys %stored) {
            $changed_obj->{$key} = $stored{$key};
        }
    }
    elsif ($changed_aspect eq "load") {
        UR::Object::unload($changed_obj);
    }
    elsif ($changed_aspect eq "load_external") {
    }
    elsif ($changed_aspect eq "unload") {
        $changed_obj = $UR::Context::current->_construct_object($changed_class_name,%$changed_obj);
        UR::Object::__signal_change__($changed_obj,"load") if $changed_obj;
    } elsif ($changed_aspect eq "commit") {
        if ($changed_obj->isa('UR::Context::Transaction')) {
            UR::Object::unload($changed_obj);
        } else {
            Carp::confess();
        }
    } elsif ($changed_aspect eq "rollback") {
        Carp::confess();
    } elsif ($changed_aspect eq 'rewrite_module_header') {
        my $VAR1;
        eval $undo_data;
        my $filename = $VAR1->{'path'};
        my $data = $VAR1->{'data'};

        if (defined $data) { 
            # The file previously existed, restore the old contents
            my $f = IO::File->new(">$filename");
            unless ($f) {
                Carp::confess("Can't open $filename for writing while undo on rewrite_module_header for class $changed_class_name: $!");
            }
            $f->print($data);
            $f->close();

        } else {
            # The file did not previously exist, remove the file
            unlink($filename);
        }
    }
    else {
        # regular property
        if ($changed_obj->can($changed_aspect)) {
            $changed_obj->$changed_aspect($undo_data);
        }
    }

    return 1;
}

1;
