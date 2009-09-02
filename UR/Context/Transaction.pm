package UR::Context::Transaction;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => ['UR::Context'],
    has => [
        begin_point     => {},
        end_point       => {is_optional => 1},  # FIXME is this ever used anywhere?
        state           => {}, # open, committed, rolled-back
    ],
    is_transactional => 1,
);

our $log_all_changes = 0;
our @change_log;
our @open_transaction_stack;
our $last_transaction_id = 0;

sub begin 
{
    my $class = shift;
    #my $id = $last_transaction_id++;
    my $id = @open_transaction_stack;

    my $begin_point = @change_log;
    $log_all_changes = 1;

    my $self = $class->create(
        id => $id,
        begin_point => $begin_point,
        state => "open",
        @_
    );

    unless ($self) {
        Carp::confess("Failed to being transaction!");
    }

    push @open_transaction_stack, $self;
    return $self;
}

sub log_change
{
    my $this_class = shift;
    my ($object, $class, $id, $aspect, $undo_data) = @_;

    return if $class eq "UR::Change";

    # wrappers (create/delete/load/unload/define) signal change also
    # and we undo the wrapper, thereby undoing these
    # -> ignore any signal from a method which is wrapped by another signalling method which gets undone
    return if ($aspect eq "create_object" or
               $aspect eq "delete_object" or
               $aspect eq "load" or
               $aspect eq "load_external"
              );

    if (!ref($object) or $class eq "UR::Object::Index") {
        #print "skipping @_\n";
        return;
    }
    #print "logging: @_\n";

    if ($aspect eq "delete") {
        $undo_data = Data::Dumper::Dumper($object);
    }

    Carp::confess() if ref($class);

    my $change = UR::Change->create(
        id => scalar(@change_log)+1,
        changed_class_name => $class,
        changed_id => $id,
        changed_aspect => $aspect,
        undo_data => $undo_data,
    );

    unless (ref($change)) {
        $DB::single = 1;
    }

    push @change_log, $change;
    return $change;
}

sub has_changes {
    my $self = shift;
    my @changes = $self->get_changes();
    return (@changes > 1 ? 1 : ());
}

sub get_changes
{
    my $self = shift;
    my $begin_point = $self->begin_point;
    my $end_point = $self->end_point || $#change_log;
    my @changes = @change_log[$begin_point..$end_point];
    if (@_) {
        @changes = UR::Change->get(id => \@changes, @_)
    }
    else {
        return @changes;
    }
}

sub get_change_summary
{
    # TODO: This should compress multiple changes to the same object as much as possible
    # Right now, it just omits the creation event for the transaction object itself.
    # -> should the creation of the transaction be part of it?
    # A: It should really be part of the prior transaction, and after commit/rollback
    #    the nesting collapses.  The @change_log should be _inside the transaction object,
    #    or the change should contain a transaction id.  The list can be destroyed on
    #    rollback, or summarized on commit.
    my $self = shift;
    my @changes =
        grep { $_->changed_aspect !~ /^(load|define)$/ }
        $self->get_changes;
    shift @changes; # $self creation event
    return @changes;
}

sub rollback
{
    my $self = shift;

    # Support calling as a class method: UR::Context::Transaction->rollback rolls back the current trans
    unless (ref($self)) {
        $self = $open_transaction_stack[-1];
        unless ($self) {
            Carp::confess("No open transaction!?  Cannot rollback.");
        }
    }

    my $begin_point = $self->begin_point;
    unless ($self eq $open_transaction_stack[-1]) {
        # This is not the top transaction on the stack.
        # Rollback internally nested transactions in order from the end.
        my @later_transactions =
            sort { $b->begin_point <=> $a->begin_point }
            $self->class->get(
                begin_point =>   { operator => ">", value => $begin_point }
            );
        for my $later_transaction (@later_transactions) {
            if ($later_transaction->isa("UR::DeletedRef")) {
                $DB::single = 1;
            }
            $later_transaction->rollback;
        }
    }

    # Reverse each change, starting from the most recent, and
    # ending with the creation of the transaction object itself.
    local $log_all_changes = 0;

    my @changes_to_undo = reverse $self->get_changes();
    for my $change (@changes_to_undo) {
        $change->undo;
        $change->delete;
    }

    $#change_log = $begin_point-1;

    unless($self->isa("UR::DeletedRef")) {
        $DB::single = 1;
        Carp::confess("Odd number of changes after rollback");
    }

    #pop @open_transaction_stack;

    return 1;
}

sub commit
{
    my $self = shift;

    # Support calling as a class method: UR::Context::Transaction->commit commits the current transaction.
    unless (ref($self)) {
        $self = $open_transaction_stack[-1];
        unless ($self) {
            Carp::confess("No open transaction!?  Cannot commit.");
        }
    }

    if ($self->state ne "open") {
        Carp::confess("Transaction not open!?")
    }

    unless ($open_transaction_stack[-1] == $self) {
        # TODO: decide if this should work like rollback, and commit nested transactions automatically
        Carp::confess("Cannot commit a transaction with open sub-transactions!");
    }

    $self->state("committed");
    #pop @open_transaction_stack;
    #$self->delete();
    return 1;
}

sub execute
{
    my $class = shift;
    Carp::confess("Attempt to call class method on instance.  This is probably not what you want...") if ref $class;
    my $code = shift;
    my $transaction = $class->begin;
    my $result = eval($code->());
    unless ($result) {
        $transaction->rollback;
    }
    if ($@) {
        die $@;
    }
    $transaction->commit;
    return $result;
}

sub execute_and_rollback
{
    my $class = shift;
    Carp::confess("Attempt to call class method on instance.  This is probably not what you want...") if ref $class;
    my $code = shift;
    my $transaction = $class->begin;
    my $result = eval($code->());
    $transaction->rollback;
    if ($@) {
        die $@;
    }
    return $result;
}

1;


1;

