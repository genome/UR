package UR::Object::View::Lister::Text;

use strict;
use warnings;
use IO::File;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Object::View',
    has_optional => [
        buf => { is => 'String' },
    ],
);


sub _create_widget {
    my $self = shift;
    my $fh = IO::File->new('>-');
    return $fh;
}

sub _update_widget_from_subject {
    my $self = shift;
    my @changes = @_;  # this is not currently resolved and passed-in
    
$DB::single=1;
    my $subject = $self->subject();
    my $subject_class_meta = $subject->__meta__;
    my @aspects = $self->aspects;
    
    my %data_for_this_object;
    my(%aspects_requiring_joins_by_name,%aspects_requiring_joins_by_via);
    my %column_for_label;
    for (my $i = 0; $i < @aspects; $i++) {
        my $aspect = $aspects[$i];
        my $label = $aspect->label;
        $column_for_label{$label} = $i;

        my $property_meta = $subject_class_meta->property_meta_for_name($label);
        if (my $via = $property_meta->via and $property_meta->is_many) {
            $aspects_requiring_joins_by_name{$label} = $via;
            $aspects_requiring_joins_by_via{$via} ||= [];
            push @{$aspects_requiring_joins_by_via{$via}}, $label;
        }

        my $aspect_name = $aspect->name;
        if ($subject) {
            my @value = $subject->$aspect_name;
            if (@value == 1 and ref($value[0]) eq 'ARRAY') {
                @value = @{$value[0]};
            }
                
            # Delegate to a subordinate viewer if need be
            if ($aspect->delegate_viewer_id) {
                my $delegate_viewer = $aspect->delegate_viewer;
                foreach my $value ( @value ) {
                    $delegate_viewer->set_subject($value);
                    $delegate_viewer->_update_widget_from_subject();
                    $value = $delegate_viewer->buf();
                }
            }

            if (@value == 1) {
                $data_for_this_object{$label} = $value[0];
            } else {
                $data_for_this_object{$label} = \@value;
            }
        }
    }

    if (keys(%aspects_requiring_joins_by_via) > 1) {
        $self->error_message("Viewing delegated properties via more than one property is not supported");
        return;
    }

    # fill in the first row of data
    my @retval = ();
    foreach my $aspect ( @aspects ) {
        my $label = $aspect->label;
        my $col = $column_for_label{$label};
        if (ref($data_for_this_object{$label})) {
            # it's a multi-value
            $retval[0]->[$col] = shift @{$data_for_this_object{$label}};
        } else {
            $retval[0]->[$col] = $data_for_this_object{$label};
        }
    }

    foreach my $via ( keys %aspects_requiring_joins_by_via ) {
         
        while(1) {
            my @this_row;
            foreach my $prop ( @{$aspects_requiring_joins_by_via{$via}} ) {
                my $data;
                if (ref($data_for_this_object{$prop}) eq 'ARRAY') {
                    $data = shift @{$data_for_this_object{$prop}};
                    next unless $data;
                } else {
                    $data = $data_for_this_object{$prop};
                    $data_for_this_object{$prop} = [];
                }
                $this_row[$column_for_label{$prop}] = $data;
            }
            last unless @this_row;
            push @retval, \@this_row;
        }

    }

    foreach my $row ( @retval ) {
        no warnings 'uninitialized';
        $row = join("\t",@$row);
    }

    my $text = join("\n", @retval);

    # The text widget won't print anything until show(),
    # so store the data in the buffer for now
    $self->buf($text);
    return 1;
}

sub _update_subject_from_widget {
    1;
}

sub _add_aspect {
    1;
}

sub _remove_aspect {
    1;
}

sub show {
    my $self = shift;
    my $fh = $self->widget;
    return unless $fh;

    $fh->print($self->buf,"\n");
}



1;

