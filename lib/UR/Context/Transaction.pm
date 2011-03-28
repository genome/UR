package UR::Context::Transaction;

use strict;
use warnings;

require UR;
our $VERSION = "0.30"; # UR $VERSION;

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

sub delete {
    my $self = shift;
    $DB::single = 1;
    $self->rollback;
}

sub begin 
{
    my $class = shift;
    my $id = $last_transaction_id++;
    #my $id = @open_transaction_stack;

    my $begin_point = @change_log;
    $log_all_changes = 1;

    my $last_trans = $open_transaction_stack[-1];
    if ($last_trans and $last_trans != $UR::Context::current) {
        die "Current transaction does not match the top of the transaction stack!?"
    }
    $last_trans ||= $UR::Context::current;

    my $self = $class->create(
        id => $id,
        begin_point => $begin_point,
        state => "open",
        parent => $last_trans,
        @_
    );

    unless ($self) {
        Carp::confess("Failed to being transaction!");
    }

    push @open_transaction_stack, $self;

    $UR::Context::current = $self;

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
    return if ( $aspect eq "load" or
               $aspect eq "load_external"
              );

    if (!ref($object) or $class eq "UR::Object::Index") {
        #print "skipping @_\n";
        return;
    }

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

    if ($self->state ne "open") {
        Carp::confess("Cannot rollback a transaction that is " . $self->state . ".")
    }

    $self->__signal_change__('prerollback');

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

    my $parent = $self->parent;
    if ($open_transaction_stack[-2] and $open_transaction_stack[-2] != $parent) {
        die "Parent transaction $parent is not below this one on the stack $open_transaction_stack[-2]?";
    }

    # Reverse each change, starting from the most recent, and
    # ending with the creation of the transaction object itself.
    local $log_all_changes = 0;


    $self->__signal_change__('rollback', 1);
    my @changes_to_undo = reverse $self->get_changes();
    my $transaction_change = pop @changes_to_undo;
    my $transaction = $transaction_change->changed_class_name->get($transaction_change->changed_id);
    unless ($self == $transaction && $transaction_change->changed_aspect eq 'create') {
        die "First change was not the creation of this transaction!";
    }
    for my $change (@changes_to_undo) {
        if ($change == $changes_to_undo[0]) {
            # the transaction reverses itself in its own context,
            # but the removal of the transaction itself happens in the parent context
            $UR::Context::current = $parent;
        }

        $change->undo;
        $change->delete;
    }

    for my $change (@changes_to_undo) {
        unless($change->isa('UR::DeletedRef')) {
            Carp::confess("Failed to undo a change during transaction rollback.");
        }
    }

    $transaction_change->undo;
    $transaction_change->delete;

    $#change_log = $begin_point-1;

    unless($self->isa("UR::DeletedRef")) {
        $DB::single = 1;
        Carp::confess("Failed to remove transaction during rollback.");
    }

    pop @open_transaction_stack;
    $UR::Context::current = $parent;

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
        Carp::confess("Cannot commit a transaction that is " . $self->state . ".")
    }

    unless ($open_transaction_stack[-1] == $self) {
        # TODO: decide if this should work like rollback, and commit nested transactions automatically
        Carp::confess("Cannot commit a transaction with open sub-transactions!");
    }
    $self->__signal_change__('precommit');

    $self->state("committed");
    if ($self->state eq 'committed') {
        $self->__signal_change__('commit',1);
    }
    else {
        $self->__signal_change__('commit',0);
    }
    pop @open_transaction_stack;
    #$self->delete();

    $UR::Context::current = $self->parent;
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

=pod

=head1 NAME

UR::Context::Transaction - API for software transactions

=head1 SYNOPSIS

  my $o = Some::Obj->create(foo => 1);
  print "o's foo is ",$o->foo,"\n";  # prints 1

  my $t = UR::Context::Transaction->begin();

  $o->foo(4);

  print "In transaction, o's foo is ",$o->foo,"\n";  # prints 4

  if (&should_we_commit()) {
      $t->commit();
      print "Transaction committed, o's foo is ",$o->foo,"\n";  # prints 4

  } else {
      $t->rollback();
      print "Transaction rollback, o's foo is ",$o->foo,"\n";  # prints 1
  }

=head1 DESCRIPTION

UR::Context::Transaction instances represent in-memory transactions as a diff
of the contents of the object cache in the Process context.  Transactions are
nestable.  Their instances exist in the object cache and  are subject to the
same scoping rules as other UR-based objects, meaning that they do not
disappear mearly because the lexical variable they're assigned to goes out of
scope.  They must be explicitly disposed of via the commit or rollback methods.

=head1 INHERITANCE

UR::Context::Transaction is a subclass of UR::Context

=head1 CONSTRUCTOR

=over 4

=item begin

  $t = UR::Context::Transaction->begin();

Creates a new software transaction context to track changes to UR-based
objects.  As all activity to objects occurs in some kind of transaction
context, the newly created transaction exists within whatever context was
current before the call to begin().

=back

=head1 METHODS

=over 4

=item commit

  $t->commit();

Causes all objects with changes to save those changes back to the underlying
context.  

=item rollback

  $t->rollback();

Causes all objects with changes to have those changes reverted to their
state when the transaction began.  Classes with properties whose meta-property
is_transactional => 0 are not tracked within a transaction and will not be
reverted.

=item delete

  $t->delete();

delete() is a synomym for rollback

=item has_changes

  $bool = $t->has_changes();

Returns true if any UR-based objects have changes within the transaction.

=item get_changes

  @changes = $t->get_changes();

Return a list or L<UR::Change> objects representing changes within the transaction.

=back

=head1 CLASS METHODS

=over 4

=item execute

  $retval = UR::Context::Transaction->execute($coderef);

Executes the coderef with no arguments, within an eval and a software
transaction.  If the coderef returns true, the transaction is committed.
If it returns false, the transaction is rolled back.  Finally the coderef's
return value is returned to the caller.

If the coderef throws an exception, it will be caught, the transaction rolled
back, and the exception will be re-thrown with die().

=item execute_and_rollback

  UR::Context::Transaction->execute_and_rollback($coderef);

Executes the coderef with no arguments, within an eval and a software
transaction.  Reguardless of the return value of the coderef, the transaction
will be rolled back.

If the coderef throws an exception, it will be caught, the transaction rolled
back, and the exception will be re-thrown with die().

=back

=head1 SEE ALSO

L<UR::Context>

=cut
