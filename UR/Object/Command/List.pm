package UR::Object::Command::List;

use strict;
use warnings;

use above "UR";                 

use Data::Dumper;
require Term::ANSIColor;

class UR::Object::Command::List {
    is => 'UR::Object::Command::FetchAndDo',
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
        doc => 'Style of the list: text (default), csv, pretty',
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

sub help_brief {
    return "Fetches objects and lists them";
}

sub help_detail {
    my $self = shift;
    
    return join(
        "\n",
        $self->_filter_doc,
        $self->_style_doc,
    );
}

sub _style_doc {
    return <<EOS;
Listing Styles:
---------------
 text - table like
 csv - comma separated values
 pretty - objects listed singly with color enhancements

EOS
}

##############################

sub valid_styles {
    return (qw/ text csv pretty /);
}
    
sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);

    # validate style
    $self->error_message( 
        sprintf(
            'Invalid style (%s).  Please choose from: %s', 
            $self->style, 
            join(', ', valid_styles()),
        ) 
    ) 
        and return unless grep { $self->style eq $_ } valid_styles();
     
    return $self;
}

sub _do
{
    my ($self, $iterator) = @_;    

    # Determine things to show
    if ( my $show = $self->show ) {
        $self->show([ map { lc } split(/,/, $show) ]);
        #TODO validate things to show??
    }
    else {
        $self->show([ map { $_->property_name } $self->_subject_class_filterable_properties ]);
    }
    
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
    # old code:
    my @show;
    my $cnt = '0 but true';
    unless ($self->format eq 'none') {
        no warnings; # lots of undefs as strings below
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

sub _create_handle_for_pretty {
    return shift->_create_handle("| cat");
}

# Header
sub _get_header_string_for_text {
    my $self = shift;

    return join (
        "\n",
        join("\t", map { uc } @{$self->show}),
        join("\t", map { '-' x length } @{$self->show}),
    );
}

sub _get_header_string_for_csv {
    my $self = shift;

    return join(",", map { lc } @{$self->show});
}

sub _get_header_string_for_pretty {
    return '';
}

# Body 
sub _object_properties_to_string {
    my ($self, $object, $char) = @_;
    my @v;
    return join(
        $char, 
        map { 
                @v = map { defined $_ ? $_ : 'NULL' } $object->$_;
                if (@v > 1) {
                    join(',',@v)
                }
                else {
                    $v[0]
                }
            } @{$self->show}
    );
}

sub _get_text_string_for_object {
    my ($self, $object) = @_;

    return $self->_object_properties_to_string($object, "\t");
}

sub _get_csv_string_for_object {
    my ($self, $object) = @_;

    return $self->_object_properties_to_string($object, ',');
}

sub _get_pretty_string_for_object {
    my ($self, $object) = @_;

    my $out;
    for my $property ( @{$self->show} )
    {
        $out .= sprintf(
            "%s: %s\n",
            Term::ANSIColor::colored($property, 'red'),
            Term::ANSIColor::colored($object->$property, 'cyan'),
        );
    }

    return $out;

    #Genome::Model::EqualColumnWidthTableizer->new->convert_table_to_equal_column_widths_in_place( \@out );
}

1;

=pod

=head1 Name

UR::Object::Command::List

=head1 Synopsis

Fetches and lists objects in different styles.

=head1 Usage

 package MyLister;

 use strict;
 use warnings;

 use above "UR";

 class MyLister {
     is => 'UR::Object::Command::List',
     has => [
     # add/modify properties
     ],
 };

 1;

=head1 Provided by the Developer

=head2 subject_class_name (optional)

The subject_class_name is the class for which the objects will be fetched.  It can be specified one of two main ways:

=over

=item I<by_the_end_user_on_the_command_line>

For this do nothing, the end user will have to provide it when the command is run.

=item I<by_the_developer_in the_class_declartion>

For this, in the class declaration, add a has key w/ arrayref of hashrefs.  One of the hashrefs needs to be subject_class_name.  Give it this declaration:

 class MyFetchAndDo {
     is => 'UR::Object::Command::FetchAndDo',
     has => [
         subject_class_name => {
             value => <CLASS NAME>,
             is_constant => 1,
         },
     ],
 };

=back

=head2 show (optional)
 
Add defaults to the show property:

 class MyFetchAndDo {
     is => 'UR::Object::Command::FetchAndDo',
     has => [
         show => {
             default_value => 'name,age', 
         },
     ],
 };

=head2 helps (optional)

Overwrite the help_brief, help_synopsis and help_detail methods to provide specific help.  If overwiting the help_detail method, use call '_filter_doc' to get the filter documentation and usage to combine with your specific help.

=head1 List Styles

text, csv, pretty (inprogress)

=head1 Disclaimer

Copyright (C) 2005 - 2008 Washington University Genome Sequencing Center

This module is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY or the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

=head1 Author(s)

B<Eddie Belter> I<ebelter@watson.wustl.edu>

=cut


#$HeadURL: svn+ssh://svn/srv/svn/gscpan/perl_modules/trunk/UR/Object/Command/List.pm $
#$Id: List.pm 36719 2008-07-17 23:43:20Z ssmith $
