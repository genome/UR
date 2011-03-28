package UR::DataSource::Default;

use strict;
use warnings;
use UR;
our $VERSION = "0.30"; # UR $VERSION;

class UR::DataSource::Default {
    is => ['UR::DataSource'],
    doc => 'allows the class to describe its own loading strategy'
};

sub _generate_template_data_for_loading {
    my ($self, $bx_template) = @_;
    my ($primary,@addl) = $self->SUPER::_generate_template_data_for_loading($bx_template);
    $primary->{needs_further_boolexpr_evaluation_after_loading} = 1;
    my $all_possible_headers = $primary->{loading_templates}[0]{property_names};
    my $expected_headers;
    my $class_meta = $bx_template->subject_class_name->__meta__;
    for my $pname (@$all_possible_headers) {
        my $pmeta = $class_meta->property($pname);
        if ($pmeta->is_delegated) {
            next;
        }
        push @$expected_headers, $pname;
    }
    $primary->{loading_templates}[0]{property_names} = $expected_headers;
    return $primary unless wantarray;
    return ($primary,@addl);
}

sub create_iterator_closure_for_rule {
    my($self,$rule) = @_;

    my $subject_class_name = $rule->subject_class_name;
    unless ($subject_class_name->can('__load__')) {
        Carp::confess("$subject_class_name does not implement __load__!!!!");
    }

    my $template = $rule->template;
    my ($loading_info) = $self->_get_template_data_for_loading($template);
    
    my $expected_headers = $loading_info->{loading_templates}[0]{property_names};
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
        my @mapping = _map_fields($headers,$expected_headers);
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

sub _map_fields {
    my ($from,$to) = @_;
    my $n = 0;
    my %from = map { $_ => $n++ } @$from;
    my @pos;
    for my $field (@$to) {
        my $pos = $from{$field};
        unless (defined $pos) {
            print "@$from\n@$to\n" . Carp::longmess() . "\n";
            die "Field not found $field!";
        }
        push @pos, $pos;
    }
    return @pos;
}

sub _sync_database {
    my $self = shift;
    my %params = @_;
    my $changed_objects = $params{changed_objects};

    my @saved;
    eval {
        for my $obj ($changed_objects) {
            push @saved, $obj;
            $obj->__save__;
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

