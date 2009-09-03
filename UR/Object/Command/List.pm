#!/gsc/bin/perl

package UR::Object::Command::List;

use strict;
use warnings;

use above "Genome";                 

class UR::Object::Command::List {
    is => 'Command',
    is_abstract => 1,
    has => [
        subject_class  => { is => 'UR::Object::Type', id_by => 'subject_class_name' }, 
    ],
    has_optional => [
        filter              => { is => 'Text',      doc => 'Limit which items are returned.' },
        show                => { is => 'Text',      doc => 'Specify which columns to show, in order.' },
        format              => { is => 'Text',      doc => 'Controls the formatting of the report.  By default, plain text.', default_value => 'text' },
        #'summarize'        => { is => 'String',    doc => 'A list of show columns by which intermediate groupings (sub-totals, etc.) should be done.' },
        #'summary_placement => { is => 'String',    doc => 'Either "top" or "bottom" or "middle".  Middle is the default.', default_value => 'middle' },
        'rowlimit'         => { is => 'Integer',   doc => 'Limit the size of the list returned to n rows.' },
    ], 
};

sub sub_command_sort_position { 0 }

sub help_brief {         
    my $self = shift;
    if (!ref($self)) {
        return "list items of various types, with controls for filtering and grouping"
    }
    else {
        my $class = $self->subject_class_name;
        my $doc = $class->get_class_object->doc;
        return $doc;
    }
}

sub help_synopsis {       
#    return <<EOS
#EOS
}

sub help_detail {          
    my $self = shift;
    my $class = $self->subject_class_name;
    if (!$class) {
        "list items of various types, with controls for filtering and grouping"
    }
    else {
        my $doc = $class->get_class_object->doc;
        return $doc;
    }
}

sub execute {  
    my $self = shift;    
    $DB::single = 1;
    
    my $subject_class_name = $self->subject_class_name;

    my $show = $self->show;
    my @show = split(/,/,$show);
    
    my $filter = $self->filter;
    my @filter = _command_line_filter_string_to_key_op_value_list($filter);
    my ($filter_boolexpr, %extra) = UR::BoolExpr->create_from_command_line_format_filters($subject_class_name,@filter);

    if (my @extra = sort keys %extra
            #sort { $a cmp $b } 
                #( (grep { not $subject_class_name->can($_) } @show), (keys %extra) )
    ) {
        for my $extra (@extra) {
            $self->error_message("Unrecognized field $extra.");
        }
        return;
    }

    my $iterator = $subject_class_name->create_iterator(
        where => $filter_boolexpr,
        #optimize_for => \@show,
    );
    
    unless ($iterator) {
        $self->error_message("Failed to create iterator: " . $subject_class_name->error_message);
        return;
    }

    my $cnt = '0 but true';
    unless ($self->format eq 'none') {
        # TODO: replace this with views, and handle terminal output as one type     
        if ($self->format eq 'text') {
            my $h = IO::File->new("| tab2col --nocount");
            $h->print(join("\t",map { uc($_) } @show),"\n");
            $h->print(join("\t",map { '-' x length($_) } @show),"\n");
            while (my $obj = $iterator->next) {  
                my $row = join("\t",map { $obj->$_ } @show) . "\n";
                $h->print($row);
                $cnt++;
            }
            $h->close;
        }
        else {
            # todo: switch this to not use App::Report
            require App;
            my $report = App::Report->create();
            my $title = $subject_class_name->get_class_object->type_name;
            $title =~ s/::/ /g;
            my $v = $self->get_class_object->get_namespace->get_vocabulary;
            $title = join(" ", $v->convert_to_title_case(split(/\s+/,$title)));
            my $section1 = $report->create_section(title => $title);
            $section1->header($v->convert_to_title_case(map { lc($_) } @show));
            while (my $obj = $iterator->next) {
                $section1->add_data(map { $obj->$_ } @show);
            }
            $cnt++;
            print $report->generate(format => ucfirst(lc($self->format)));
        }
    }
    # This replaces tab2col's item count, since it counts the header also
    print "$cnt rows output\n";
    return $cnt; 
}

sub _command_line_filter_string_to_key_op_value_list {
    my $filter_string = shift;
    my ($property, $op, $fof_indicator, $value);
    no warnings;
    my @filter =
        map {
            unless (
                ($property, $op, $value) =
                    ($_ =~ /^\s*(\w+)\s*(\@|\=|!=|=|\>|\<|~|\:|\blike\b)\s*(.*)\s*$/)
            ) {
                die "Unable to process filter $_\n";
            }
            $op = "like" if $op eq "~";

            [$property,$op,$value]
        }
        split(/,/,$filter_string);
    return @filter;
}

1;
