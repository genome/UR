package UR::DataSource::Default;

# NOTE: UR::DataSource::QueryPlan currently has conditional logic for this class

use strict;
use warnings;
use UR;
our $VERSION = "0.41_02"; # UR $VERSION;

class UR::DataSource::Default {
    is => ['UR::DataSource','UR::Singleton'],
    doc => 'allows the class to describe its own loading strategy'
};


sub create_iterator_closure_for_rule {
    my($self,$rule) = @_;

    my $subject_class_name = $rule->subject_class_name;
    unless ($subject_class_name->can('__load__')) {
        Carp::croak("Can't load from class $subject_class_name: UR::DataSource::Default requires the class to implement __load__");
    }

    my $template = $rule->template;
    my ($query_plan) = $self->_resolve_query_plan($template);
    
    my $expected_headers = $query_plan->{loading_templates}[0]{property_names};
    my ($headers, $content) = $subject_class_name->__load__($rule,$expected_headers);

    my $iterator;
    if (ref($content) eq 'ARRAY') {
        $iterator = sub {
            my $next_row = shift @$content;
            $content = undef if @$content == 0;
            return $next_row;
        };
    }
    elsif (ref($content) eq 'CODE') {
        $iterator = $content;
    }
    else {
        Carp::confess("Expected an arrayref of properties, and then content in the form of an arrayref (rows,columns) or coderef/iterator returning rows from $subject_class_name __load__!\n");
    }

    if ("@$headers" ne "@$expected_headers") {
        # translate the headers into the appropriate order
        my @mapping = eval { _map_fields($headers,$expected_headers);};
        if ($@) {
            Carp::croak("Loading data for class $subject_class_name and boolexpr $rule failed: $@");
        }
        # print Data::Dumper::Dumper($headers,$expected_headers,\@mapping);
        my $orig_iterator = $iterator;
        $iterator = sub {
            my $result = $orig_iterator->();
            return unless $result;
            my @result2 = @$result[@mapping];
            return \@result2;
        };
    }

    return $iterator;
}

sub can_savepoint { 0 }

sub _map_fields {
    my ($from,$to) = @_;
    my $n = 0;
    my %from = map { $_ => $n++ } @$from;
    my @pos;
    for my $field (@$to) {
        my $pos = $from{$field};
        unless (defined $pos) {
            #print "@$from\n@$to\n" . Carp::longmess() . "\n";
            die("Can't resolve value for '$field' from the headers returned by its __load__: ". join(', ', @$from));
        }
        push @pos, $pos;
    }
    return @pos;
}

# Nothing to be done for commit and rollback
sub rollback { 1;}
sub commit   { 1; }

sub _sync_database {
    my $self = shift;
    my %params = @_;
    my $changed_objects = $params{changed_objects};

    my %class_can_save;
    my @saved;
    eval {
        for my $obj (@$changed_objects) {
            my $obj_class = $obj->class;
            unless (exists $class_can_save{$obj_class}) {
                $class_can_save{$obj_class} = $obj->can('__save__');
            }
            if ($class_can_save{$obj_class}) {
                push @saved, $obj;
                $obj->__save__;
            }
        }
    };

    if ($@) {
        my $err = $@;
        my @failed_rollback;
        while (my $obj = shift @saved) {
            eval {
                $obj->__rollback__;
            };
            if ($@) {
                push @failed_rollback, $obj;
            }
        }
        if (@failed_rollback) {
            print Data::Dumper::Dumper("Failed Rollback:", \@failed_rollback);
            die "Failed to save, and ERRORS DURING ROLLBACK:\n$err\n $@\n";
        }
        die $@;
    }


    my @failed_commit;
    unless ($@) {
        # all saves worked, commit
        while (my $obj = shift @saved) {
            eval {
                $obj->__commit__;
            };
            if ($@) {
                push @failed_commit, $@ => $obj;
            }
        };
    }

    return 1;
}

1;

