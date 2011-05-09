package UR::Context::LoadingIterator;

use strict;
use warnings;

use UR::Context;

our $VERSION = "0.31"; # UR $VERSION;

# A helper package for UR::Context to handling queries which require loading
# data from outside the current context.  It is responsible for collating 
# cached objects and incoming objects.  When create_iterator() is used in
# application code, this is the iterator that gets returned
# 
# These are normal Perl objects, not UR objects, so they get regular
# refcounting and scoping

our @CARP_NOT = qw( UR::Context );

# A boolean flag used in the loading iterator to control whether we need to
# inject loaded objects into other loading iterators' cached lists
my $is_multiple_loading_iterators = 0;

my %all_loading_iterators;


# Some thoughts about the loading iterator's behavior around changing objects....
#
# The system attempts to return objects matching the rule at the time the iterator is
# created, even if they change between the time it's created and when next() returns 
# them.  There is a problem if the object in question is actually deleted (ie. isa
# UR::DeletedRef).  Since DeletedRef's die any time you try to use them, the object
# sorters can't sort them.  Instead, we'll just punt and throw an exception ourselves
# if we come across one.
# 
# This seems like the least suprising thing to do, but there are other solutions:
# 1) just plain don't return the deleted object
# 2) use signal_change to register a callback which will remove objects being deleted
#    from all the in-process iterator @$cached lists (accomplishes the same as #1).
#    For completeness, this may imply that other signal_change callbacks would remove
#    objects that no longer match rules for in-process iterators, and that means that 
#    next() returns things true at the time next() is called, not when the iterator
#    is created.
# 3) Put in some additional infrastructure so we can pull out the ID of a deleted
#    object.  That lets us call $next_object->id at the end of the closure, and return these
#    deleted objects back to the user.  Problem being that the user then can't really
#    do anything with them.  But it would be consistent about returning _all_ objects
#    that matched the rule at iterator creation time
# 4) Like #3, but just always return the deleted object before any underlying_context
#    object, and then don't try to get its ID at the end if the iterator if it's deleted



sub _create {
    my($class, $cached, $context, $normalized_rule, $data_source, $this_get_serial ) = @_;


    my $underlying_context_iterator = $context->_create_import_iterator_for_underlying_context(
              $normalized_rule, $data_source, $this_get_serial);

    my $is_monitor_query = $context->monitor_query;

    # These are captured by the closure...
    my($last_loaded_id, $next_obj_current_context, $next_obj_underlying_context);

    my $object_sorter = $normalized_rule->template->sorter();

    my $me_loading_iterator_as_string;  # See note below the closure definition

    my $underlying_context_objects_count = 0;
    my $cached_objects_count = 0;

    my $loading_iterator = sub {

        PICK_NEXT_OBJECT_FOR_LOADING:
        if ($underlying_context_iterator && ! $next_obj_underlying_context) {
            ($next_obj_underlying_context) = $underlying_context_iterator->(1);

            $underlying_context_objects_count++ if ($is_monitor_query and $next_obj_underlying_context);

            # See if this newly loaded object needs to be inserted into any of the other
            # loading iterators' cached list.  We only need to check this is there is more
            # than one iterator running....
            if ($next_obj_underlying_context and $is_multiple_loading_iterators) {
                $class->_inject_object_into_other_loading_iterators($next_obj_underlying_context, $me_loading_iterator_as_string);
            }
        }

        unless ($next_obj_current_context) {
            ($next_obj_current_context) = shift @$cached;
            $cached_objects_count++ if ($is_monitor_query and $next_obj_current_context);
        }

        if ($next_obj_current_context and $next_obj_current_context->isa('UR::DeletedRef')) {
             my $obj_to_complain_about = $next_obj_current_context;
             # undef it in case the user traps the exception, next time we'll pull another off the list
             $next_obj_current_context = undef;
             Carp::croak("Attempt to fetch an object which matched $normalized_rule when the iterator was created, "
                         . "but was deleted in the meantime:\n"
                         . Data::Dumper::Dumper($obj_to_complain_about) );
        }

        if (!$next_obj_underlying_context) {
            if ($is_monitor_query) {
                $context->_log_query_for_rule($normalized_rule->subject_class_name,
                                              $normalized_rule,
                                              "QUERY: loaded $underlying_context_objects_count object(s) total from underlying context.");
            }
            $underlying_context_iterator = undef;

        }
        elsif (defined($last_loaded_id)
               and
               $last_loaded_id eq $next_obj_underlying_context->id)
        {
            # during a get() with -hints or is_many+is_optional (ie. something with an
            # outer join), it's possible that the join can produce the same main object
            # as it's chewing through the (possibly) multiple objects joined to it.
            # Since the objects will be returned sorted by their IDs, we only have to
            # remember the last one we saw
            # FIXME - is this still true now that the underlying context iterator and/or
            # object fabricator hold off on returning any objects until all the related
            # joined data bas been loaded?
            $next_obj_underlying_context = undef;goto PICK_NEXT_OBJECT_FOR_LOADING;
        }

        # decide which pending object to return next
        # both the cached list and the list from the database are sorted separately,
        # we're merging these into one return stream here
        my $comparison_result = undef;
        if ($next_obj_underlying_context && $next_obj_current_context) {
            $comparison_result = $object_sorter->($next_obj_underlying_context, $next_obj_current_context);
        }

        my $next_object;
        if (
            $next_obj_underlying_context
            and $next_obj_current_context
            and $comparison_result == 0 # $next_obj_underlying_context->id eq $next_obj_current_context->id
        ) {
            # the database and the cache have the same object "next"
            $context->_log_query_for_rule($class, $normalized_rule, "QUERY: loaded object was already cached") if ($is_monitor_query);
            $next_object = $next_obj_current_context;
            $next_obj_current_context = undef;
            $next_obj_underlying_context = undef;
        }
        elsif (
            $next_obj_underlying_context
            and (
                (!$next_obj_current_context)
                or
                ($comparison_result < 0) # ($next_obj_underlying_context->id le $next_obj_current_context->id) 
            )
        ) {
            # db object is next to be returned
            $next_object = $next_obj_underlying_context;
            $next_obj_underlying_context = undef;
        }
        elsif (
            $next_obj_current_context
            and (
                (!$next_obj_underlying_context)
                or
                ($comparison_result > 0) # ($next_obj_underlying_context->id ge $next_obj_current_context->id) 
            )
        ) {
            # cached object is next to be returned
            $next_object = $next_obj_current_context;
            $next_obj_current_context = undef;
        }

        return unless defined $next_object;

        $last_loaded_id = $next_object->id;

        return $next_object;
    };  # end of the closure

    bless $loading_iterator, $class;
    Sub::Name::subname($class . '__loading_iterator_closure__', $loading_iterator);

    # Inside the closure, it needs to know its own address, but without holding a real reference
    # to itself - otherwise the closure would never go out of scope, the destructor would never
    # get called, and the list of outstanding loaders would never get pruned.  This way, the closure
    # holds a reference to the string version of its address, which is the only thing it really
    # needed anyway
    $me_loading_iterator_as_string = $loading_iterator . '';

    $all_loading_iterators{$me_loading_iterator_as_string} = 
        [ $me_loading_iterator_as_string,
          $normalized_rule,
          $object_sorter,
          $cached,
          \$underlying_context_objects_count,
          \$cached_objects_count,
          $context,
      ];

    $is_multiple_loading_iterators = 1 if (keys(%all_loading_iterators) > 1);

    return $loading_iterator;
} # end _create()



sub DESTROY {
    my $self = shift;

    my $iter_data = $all_loading_iterators{$self};
    if ($iter_data->[0] eq $self) {
        # that's me!

        # Items in the listref are: $loading_iterator_string, $rule, $object_sorter, $cached,
        # \$underlying_context_objects_count, \$cached_objects_count, $context

        my $context = $iter_data->[6];
        if ($context->monitor_query) {
            my $rule = $iter_data->[1];
            my $count = ${$iter_data->[4]} + ${$iter_data->[5]};
            $context->_log_query_for_rule($rule->subject_class_name, $rule, "QUERY: Query complete after returning $count object(s) for rule $rule.");
            $context->_log_done_elapsed_time_for_rule($rule);
        }
        delete $all_loading_iterators{$self};
        $is_multiple_loading_iterators = 0 if (keys(%all_loading_iterators) < 2);

    } else {
        Carp::carp('A loading iterator went out of scope, but could not be found in the registered list of iterators');
    }
}


# Used by the loading itertor to inject a newly loaded object into another
# loading iterator's @$cached list.  This is to handle the case where the user creates
# an iterator which will load objects from the DB.  Before all the data from that
# iterator is read, another get() or iterator is created that covers (some of) the same
# objects which get pulled into the object cache, and the second request is run to
# completion.  Since the underlying context iterator has been changed to never return
# objects currently cached, the first iterator would have incorrectly skipped ome objects that
# were not loaded when the first iterator was created, but later got loaded by the second.
sub _inject_object_into_other_loading_iterators {
    my($self, $new_object, $iterator_to_skip) = @_;

    ITERATOR:
    foreach my $iter_name ( keys %all_loading_iterators ) {
        next if $iter_name eq $iterator_to_skip;  # That's me!  Don't insert into our own @$cached this way
        my($loading_iterator, $rule, $object_sorter, $cached)
                                = @{$all_loading_iterators{$iter_name}};
        if ($rule->evaluate($new_object)) {

            my $cached_list_len = @$cached;
            for(my $i = 0; $i < $cached_list_len; $i++) {
                my $cached_object = $cached->[$i];
                next if $cached_object->isa('UR::DeletedRef');

                my $comparison = $object_sorter->($new_object, $cached_object);

                if ($comparison < 0) {
                    # The new object sorts sooner than this one.  Insert it into the list
                    splice(@$cached, $i, 0, $new_object);
                    next ITERATOR;
                } elsif ($comparison == 0) {
                    # This object is already in the list
                    next ITERATOR;
                }
            }

            # It must go at the end...
            push @$cached, $new_object;
        }
    } # end foreach
}


# Reverse of _inject_object_into_other_loading_iterators().  Used when one iterator detects that
# a previously loaded object no longer exists in the underlying context/datasource
sub _remove_object_from_other_loading_iterators {
    my($self, $disappearing_object, $iterator_to_skip) = @_;

#print "In _remove_object_from_other_loading_iterators, count is $iterator_count\n";
$DB::single=1;
    ITERATOR:
    foreach my $iter_name ( keys %all_loading_iterators ) {
        next if $iter_name eq $iterator_to_skip;  # That's me!  Don't remove into our own @$cached this way
        my($loading_iterator, $rule, $object_sorter, $cached)
                                = @{$all_loading_iterators{$iter_name}};
        next if (defined($iterator_to_skip)
                  and $loading_iterator eq $iterator_to_skip);  # That's me!  Don't insert into our own @$cached this way
#print "Evaluating rule $rule against object ".Data::Dumper::Dumper($disappearing_object),"\n";
        if ($rule->evaluate($disappearing_object)) {
#print "object matches rule\n";

            my $cached_list_len = @$cached;
#print "there are $cached_list_len objects in the cached list: ",join(',',map { $_->id } @$cached),"\n";
            for(my $i = 0; $i < $cached_list_len; $i++) {
                my $cached_object = $cached->[$i];
                next if $cached_object->isa('UR::DeletedRef');

                my $comparison = $object_sorter->($disappearing_object, $cached_object);

#print "cached obj id ".$cached_object->id." comparison $comparison\n";
                if ($comparison == 0) {
                    # That's the one, remove it from the list
#print "removing obj id ".$disappearing_object->id." from loading iterator $loading_iterator cache\n";
                    splice(@$cached, $i, 1);
                    next ITERATOR;
                } elsif ($comparison < 0) {
                    # past the point where we expect to find this object
                    next ITERATOR;
                }
            }
        }
    } # end foreach
}

1;


