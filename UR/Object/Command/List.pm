package UR::Object::Command::List;

use strict;
use warnings;

use above "Genome";                 

use Data::Dumper;
require Term::ANSIColor;

class UR::Object::Command::List {
    is => 'UR::Object::Command::FetchAndDo',
    is_abstract => 1,
    has => [
    show => {
        is => 'Text',
        is_optional => 1,
        doc => 'Specify which columns to show, in order.' 
    },
    style => { 
        is => 'Text',
        is_optional => 1,
        default_value => 'text',
        doc => 'Style of the list: text (default), csv',
    },
    noheaders => { 
        is => 'Boolean',
        is_optional => 1,
        default => 0,
        doc => 'Do not include headers',
    },
    #'summarize'        => { is => 'String',    doc => 'A list of show columns by which intermediate groupings (sub-totals, etc.) should be done.' },
    #'summary_placement => { is => 'String',    doc => 'Either "top" or "bottom" or "middle".  Middle is the default.', default_value => 'middle' },
    #rowlimit => {
    #    is => 'Integer', 
    #    is_optional => 1,
    #    doc => 'Limit the size of the list returned to n rows.' 
    #},
    ], 
};

##############################

sub valid_styles {
    return (qw/ text csv /);
}

sub _do
{
    my ($self, $iterator) = @_;    

    my @show;
    my @props = map { $_->property_name } $self->_subject_class_filterable_properties;
    if ( $self->show ) {
        @show = split(/,/, $self->show); 
        #TODO validate things to show
    }
    else {
        @show = @props;
    }

    # TODO set show
    $self->{_show}=\@show;

    # Handle
    my $handle_method = sprintf('_create_handle_for_%s', $self->style);
    my $h = $self->$handle_method
        or return;
     
    # Header
    unless ( $self->noheaders ) {
        my $header_method = sprintf('_get_header_string_for_%s', $self->style);
        $h->print($self->$header_method, "\n");
    }

    # Body
    my $body_method = sprintf('_get_%s_string_for_object', $self->style);
    my $count = 0;
    while (my $object = $iterator->next) {  
        $h->print($self->$body_method($object), "\n");
        $count++;
    }
    $h->close;
    #print "$count rows output\n";

    return 1;


    ################################
    ##############################
    # TODO add more views
    my $cnt = '0 but true';
    unless ($self->format eq 'none') {
        # TODO: replace this with views, and handle terminal output as one type     
        if ($self->format eq 'text') {
            my $h = IO::File->new("| tab2col --nocount");
            $h->print(join("\t",map { uc($_) } @show),"\n");
            $h->print(join("\t",map { '-' x length($_) } @show),"\n");
            while (my $obj = $iterator->next) {  
                my $row = join("\t",map { 
                        ( defined $obj->$_ ? $obj->$_ : 'NULL' )
                        } @show) . "\n";
                $h->print($row);
                $cnt++;
            }
            $h->close;
            # This replaces tab2col's item count, since it counts the header also
            print "$cnt rows output\n";
        }
        else {
            # todo: switch this to not use App::Report
            require App;
            my $report = App::Report->create();
            my $title = $self->subject_class_name->get_class_object->type_name;
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

    return $cnt; 
}

# Handle
sub _create_handle {
    my ($self, $command) = @_;
    
    my $handle = IO::File->new($command);
    $self->error_message("Can't open command handle for tab2col: $!")
        and return unless $handle;

    return $handle;
}

sub _create_handle_for_text {
    return shift->_create_handle("| tab2col --nocount");
}

sub _create_handle_for_csv {
    return shift->_create_handle("| cat");
}

# Header
sub _get_header_string_for_text {
    my $self = shift;

    return join (
        "\n",
        join("\t", map { uc } @{$self->{_show}}),
        join("\t", map { '-' x length } @{$self->{_show}}),
    );
}

sub _get_header_string_for_csv {
    my $self = shift;

    return join(",", map { lc } @{$self->{_show}});
}

# Body 
sub _object_properties_to_string {
    my ($self, $object, $char) = @_;

    return join($char, map { ( defined $object->$_ ? $object->$_ : 'NULL' ) } @{$self->{_show}});
}

sub _get_text_string_for_object {
    my ($self, $object) = @_;

    return $self->_object_properties_to_string($object, "\t");
}

sub _get_pretty_string_for_object {
    my ($self, $object) = @_;

    my $row = $self->_object_to_plain_row($object);

    return Term::ANSIColor::colored($row, 'blue');
}

sub _get_csv_string_for_object {
    my ($self, $object) = @_;

    return $self->_object_properties_to_string($object, ',');
}

1;

#$HeadURL: svn+ssh://svn/srv/svn/gscpan/perl_modules/trunk/UR/Object/Command/List.pm $
#$Id: List.pm 36255 2008-07-07 20:15:50Z ebelter $
