#####
#
# Support "Ghost" objects.  These represent deleted items which are not saved.
# They are omitted from regular class lists.
#
#####

package UR::Object::Ghost;

use strict;
use warnings;

sub _init_subclass {
    my $class_name = pop;
    no strict;
    no warnings;
    my $live_class_name = $class_name;
    $live_class_name =~ s/::Ghost$//;
    *{$class_name ."\:\:class"}  = sub { "$class_name" };
    *{$class_name ."\:\:live_class"}  = sub { "$live_class_name" };
}


sub create { die "Cannot create() ghosts.  Use create_object." }

sub delete { die "Cannot delete() ghosts.  Use delete_object." }

sub _load {
    shift->is_loaded(@_);
}

sub cache_class_path {
    return shift->live_class->cache_class_path;
}

sub unload {
    return;
}

sub edit_class { undef }

sub ghost_class { undef }

sub history_class { undef }

sub history_table_name { undef }

sub is_ghost { return 1; }

sub live_class
{
    my $class = $_[0]->class;
    $class =~ s/::Ghost//;
    return $class;
}

sub label_name { shift->live_class->label_name . "(DELETED)" }

my @ghost_changes;
sub changed {
    @ghost_changes = UR::Object::Tag->create ( type => 'changed', properties => ['id']) unless @ghost_changes;
    return @ghost_changes;
}

sub AUTOSUB
{
    # Delegate to the similar function on the regular class.
    my ($func, $self) = @_;
    my $live_class = $self->live_class;
    return $live_class->can($func);
}

1;
