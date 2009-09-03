package UR::Object::Command::List;

use strict;
use warnings;
use IO::File;

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
        output => {
            is => 'IO::Handle',
            is_optional =>1,
            is_transient =>1,
            default => \*STDOUT,
            doc => 'output handle for list, defauls to STDOUT',
        },
    ], 
    doc => 'fetches objects and lists them',
};

##############################

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
 html - html table

EOS
}

##############################

sub valid_styles {
    return (qw/ text csv pretty html/);
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
    unless ( ref $self->output ){
        my $ofh = IO::File->new("> ".$self->output);
        $self->error_message("Can't open file handle to output param ".$self->output) and die unless $ofh;
        $self->output($ofh);
    }

    return $self;
}

sub _hint_string 
{
    my $self = shift;
    return $self->show;
}

sub _do
{
    my ($self, $iterator) = @_;    

    #$DB::single = $DB::stopper;
    
    # prevent commits due to changes here
    # this can be prevented by careful use of environment variables if you REALLY want to use this to update data
    $ENV{UR_DBI_NO_COMMIT} = 1 unless (exists $ENV{UR_DBI_NO_COMMIT});

    # Determine things to show
    if ( my $show = $self->show ) {
        my @show;
        my $expr;
        for my $item (split(/,/, $show)) {
            if ($item =~ /^\w+$/ and not defined $expr) {
                push @show, $item;
            }
            else {
                if ($expr) {
                    $expr .= ',' . $item;
                }
                else {
                    $expr = '(' . $item;
                }
                my $o;
                if (eval('sub { ' . $expr . ')}')) {
                    push @show, $expr . ')';
                    #print "got: $expr<\n";
                    $expr = undef;
                }
            }
        }
        if ($expr) {
            die "Bad expression: $expr\n$@\n";
        }
        $self->show(\@show);
        
        #TODO validate things to show??
    }
    else {
        $self->show([ map { $_->property_name } $self->_subject_class_filterable_properties ]);
    }

    my $style_module_name = ucfirst $self->style;
    my $style_module = $style_module_name->new( 
        iterator =>$iterator, 
        show =>$self->show, 
        noheaders =>$self->noheaders,
        output => $self->output
    );
    $style_module->format_and_print;

    return 1;
}

package Style;

sub new{
    my ($class, %args) = @_;
    foreach (qw/iterator show noheaders output/){
        die "no value for $_!" unless defined $args{$_};
    }
    return bless(\%args, $class);
}

sub _object_properties_to_string {
    my ($self, $o, $char) = @_;
    my @v;
    return join(
        $char, 
        map { defined $_ ? $_ : '<NULL>' } 
        map { 
            if (substr($_,0,1) eq '(') {
                @v = eval $_;
                if ($@) {
                    @v = ('<ERROR>'); # ($@ =~ /^(.*)$/);
                }
            }
            else {
                @v = map { defined $_ ? $_ : '<NULL>' } $o->$_;
            }
            if (@v > 1) {
                no warnings;
                join(',',@v)
            }
            else {
                $v[0]
            }
        } @{$self->{show}}
    );
}

sub format_and_print{
    my $self = shift;

    unless ( $self->{noheaders} ) {
        $self->{output}->print($self->_get_header_string. "\n");
    }

    my $count = 0;
    while (my $object = $self->{iterator}->next) {
        $self->{output}->print($self->_get_object_string($object), "\n");
        $count++;
    }

}

package Html;
use base 'Style';

sub _get_header_string{
    my $self = shift;
    return "<tr><th>". join("</th><th>", map { uc } @{$self->{show}}) ."</th></tr>";
}

sub _get_object_string{
    my ($self, $object) = @_;
    
    my $out = "<tr>";
    for my $property ( @{$self->{show}} ){
        $out .= "<td>" . $object->$property . "</td>";
    }
    
    return $out . "</tr>";
}

sub format_and_print{
    my $self = shift;
    
    $self->{output}->print("<table>");
    
    #cannot use super because \n screws up javascript
    unless ( $self->{noheaders} ) {
        $self->{output}->print($self->_get_header_string);
    }

    my $count = 0;
    while (my $object = $self->{iterator}->next) {
        $self->{output}->print($self->_get_object_string($object));
        $count++;
    }
    
    $self->{output}->print("</table>");
}

package Csv;
use base 'Style';

sub _get_header_string{
    my $self = shift;

    return join(",", map { lc } @{$self->{show}});
}

sub _get_object_string {
    my ($self, $object) = @_;

    return $self->_object_properties_to_string($object, ',');
}

package Pretty;
use base 'Style';

sub _get_header_string{
    return '';
}

sub _get_object_string{
    my ($self, $object) = @_;

    my $out;
    for my $property ( @{$self->{show}} )
    {
        $out .= sprintf(
            "%s: %s\n",
            Term::ANSIColor::colored($property, 'red'),
            Term::ANSIColor::colored($object->$property, 'cyan'),
        );
    }

    return $out;
}

package Text;
use base 'Style';

sub _get_header_string{
    my $self = shift;
    return join (
        "\n",
        join("\t", map { uc } @{$self->{show}}),
        join("\t", map { '-' x length } @{$self->{show}}),
    );
}

sub _get_object_string{
    my ($self, $object) = @_;
    $self->_object_properties_to_string($object, "\t");
}

sub format_and_print{
    my $self = shift;
    my $tab_delimited;
    unless ($self->{noheaders}){
        $tab_delimited .= $self->_get_header_string."\n";
    }

    my $count = 0;
    while (my $object = $self->{iterator}->next) {
        $tab_delimited .= $self->_get_object_string($object)."\n";
        $count++;
    }

    $self->{output}->print($self->tab2col($tab_delimited));
}

sub tab2col{
    my ($self, $data) = @_;

    #turn string into 2d array of arrayrefs ($array[$rownum][$colnum])
    my @rows = split("\n", $data);
    @rows = map { [split("\t", $_)] } @rows;

    my $output;
    my @width;

    #generate array of max widths per column
    foreach my $row_ref (@rows) {
        my @cols = @$row_ref;
        my $index = $#cols;
        for (my $i = 0; $i <= $index; $i++) {
            my $l = (length $cols[$i]) + 3; #TODO test if we need this buffer space
            $width[$i] = $l if ! defined $width[$i] or $l > $width[$i];
        }
    }
    
    #create a array of blanks to use as a templatel
    my @column_template = map { ' ' x $_ } @width;

    #iterate through rows and cols, substituting in the row entry in your template
    foreach my $row_ref (@rows) {
        my @cols = @$row_ref;
        my $index = $#cols;
        #only apply template for all but the last entry in a row 
        for (my $i = 0; $i < $index; $i++) {
            my $entry = $cols[$i];
            my $template = $column_template[$i];
            substr($template, 0, length $entry, $entry);
            $output.=$template;
        }
        $output.=$cols[$index]."\n"; #Don't need traling spaces on the last entry
    }
    return $output;
}
1;
=pod

=head1 NAME

UR::Object::Command::List - Fetches and lists objects in different styles.

=head1 SYNOPSIS

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

text, csv, html, pretty (inprogress)

=cut


#$HeadURL: /gscpan/distro/ur-bundle/releases/UR-0.8/lib/UR/Object/Command/List.pm $
#$Id: /gscpan/distro/ur-bundle/releases/UR-0.8/lib/UR/Object/Command/List.pm 47382 2009-05-29T21:04:40.408084Z ssmith  $
