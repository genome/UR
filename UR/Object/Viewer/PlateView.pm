# Viewer for 96- or 384-well plates.
# Copyright (C) 2004 Washington University in St. Louis
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package UR::Object::Viewer::PlateView;

=pod

=head1 NAME

UR::Object::Viewer::PlateView - provides a Gtk viewer for displaying 
384 or 96 well plates, colorizing wells, and notifying applications about 
Gtk events on clickable well buttons

=head1 SYNOPSIS

  # assuming $window is a previously created gtk window

  my $plate = new UR::Object::Viewer::PlateView(plate_type=>'384 well plate');
  $window->add($plate->get_widget);
  $window->show_all();

  # wells can be passed in as eithern ames or DNA Locations

  my $dl = GSC::DNALocation->get(location_name=>'a06',
                                 location_type=>'384 well plate');

  # color all of a1 plus a few other wells light green

  $plate->set_well_color(wells=>[$dl,'h12','a07'], 
                         sectors=>['a1'], 
                         color=>'light green');

  # register a well handler
  $plate->register_well_handler(event_type=>'released',
                                code=>\&test,
                                sectors=>['a1'],
                                return_well_info=>['well_name',
                                                   'dna_location']);

=head1 DESCRIPTION

This module allows the developer to represent 384 or 96 well plates as 
sets of buttons.  Buttons representing wells can be easily colorized by 
passing in entire sets of wells, sectors, or both.

Well information can be provided as well number (e.g. well h12 = well 96) 
or as GSC::DNALocation objects.

The application can also register to be notified of gtk events, such as 
when a button is clicked and released, or when it receives mouse focus.  
This is done without exposing the internal Gtk representation to any 
application.

ToolTips can also be added to wells to present additional information when 
the user hovers their mouse over buttons.

=head1 METHODS

This module provides publicly accessible methods for setting and clearing 
well colors, registering and deregistering well handlers, and setting 
ToolTips.

=over 4

=cut

# set up package
require 5.6.0;
use warnings;
use strict;
our $VERSION = '0.1';
our (@ISA, @EXPORT, @EXPORT_OK);

# set up module
require Exporter;
@ISA= qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw();

use Gtk;

# surprisingly enough, these match dna location types
# for easier mapping to well numbers when working with 
# sectors

my $ROW_CONFIG = { '96 well plate' => {rows=>8,
                                       cols=>12},
                   '384 well plate' => {rows=>16,
                                        cols=>24}};

=pod

=item new

The constructor accepts one parameter, which is the type of plate to
view.

    my $plate = new UR::Object::Viewer::PlateView(plate_type=>'384 well plate');

Current choices are either '384 well plate' or '96 well plate'.

The constructor returns a PlateView object, which is NOT a Gtk widget.
You must use the get_widget method to obtain the actual plate viewer
widget.

=cut


sub new {

    my $class = shift;
    my %params = @_;
    
    my $self = {};

    bless $self, $class;
    
    my $plate_type = $params{plate_type};

    $self->{TBL} = new Gtk::Table($ROW_CONFIG->{$plate_type}->{rows} + 1,
                                  $ROW_CONFIG->{$plate_type}->{cols} + 1,
                                  1);

    $self->{PLATE_TYPE} = $plate_type;

    my $tbl = new Gtk::Table(9,13,1);
    $tbl->set_homogeneous(1);
    
    $self->{BUTTONS} = {}; 

    $self->{HANDLER_REGID_COUNT} = 0;

    $self->{HANDLERS} = {};

    $self->{TOOLTIPS} = new Gtk::Tooltips;

    # preload DNA locations if they're not already existent
    
    my @dls = GSC::DNALocation->get(location_type=>$self->{PLATE_TYPE});

    # lay down headers
    for (1..$ROW_CONFIG->{$plate_type}->{cols}) {
        my $lbl = new Gtk::Label("$_");
        
        $tbl->attach_defaults($lbl,$_,$_+1,0,1);
    }

    for my $r (1..$ROW_CONFIG->{$plate_type}->{rows}) {
        
        my $lbl = new Gtk::Label("".chr(ord('a') + $r-1));
        
        $tbl->attach_defaults($lbl,0,1,$r,$r+1);
        
        for my $c (1..$ROW_CONFIG->{$plate_type}->{cols}) {
            my $wellname = ($r - 1) * $ROW_CONFIG->{$plate_type}->{cols} + $c ;
            
            $self->{BUTTONS}->{$wellname} = new Gtk::Button($self->_well_number_to_well_name($wellname));
            $self->{BUTTONS}->{$wellname}->set_usize(20,25);
            $tbl->attach_defaults($self->{BUTTONS}->{$wellname},
                                  $c,$c+1,
                                  $r, $r+1);
        }
    }
    
    $self->{PLATE_WIDGET} = $tbl;
    
    my $visual = $tbl->get_visual();
    $self->{COLORMAP} = new Gtk::Gdk::Colormap($visual, 256);

    return $self;
}


=pod

=item get_widget

Returns the plate viewer widget.

=cut


sub get_widget {
    my $self = shift;

    return $self->{PLATE_WIDGET};
}


=pod

=item set_well_color

Applies a color to a set of wells, a set of plate sectors, or both.

Wells can be represented by well name ('h12'), well number (96), or by 
a GSC::DNALocation object.

The color must be a text version of a GTK color.

$plate->set_well_color(sectors=>['a1'],
                       wells=>['b2','c2',$dl],
                       color=>'lightgreen');


sectors or wells hash keys can be left undefined if unused.


=cut


sub set_well_color {
    my $self = shift;
    my %p = @_;
    
    my @wells = $self->_aggregate_well_info(sectors=>$p{sectors},
                                            wells=>$p{wells});
    
    
    die "PlateView::set_well_color requires a color" unless (defined $p{color});
    
    my $color;
    
    unless ($color = $self->{COLORS}->{$p{color}}) {
        $color = $self->{COLORMAP}->color_alloc(Gtk::Gdk::Color->parse_color($p{color}));
        $self->{COLORS}->{$p{color}} = $color;
        
        $self->{STYLES}->{$p{color}} = new Gtk::Style;
        $self->{STYLES}->{$p{color}}->bg('normal',$color);;

    } 

    
    for (@wells) {
        $self->{BUTTONS}->{$_}->set_style($self->{STYLES}->{$p{color}});
    }
    
}


=pod


=item clear_well_color

Clears a color from a set of wells, a set of plate sectors, or both.

Wells can be represented by well name ('h12'), well number (96), or by 
a GSC::DNALocation object.

$plate->clear_well_color(sectors=>['a1'],
                         wells=>['b2','c2',$dl]);


sectors or wells hash keys can be left undefined if unused.


=cut

sub clear_well_color {
    my $self = shift;
    my %p = @_;
    
    my @wells = $self->_aggregate_well_info(sectors=>$p{sectors},
                                            wells=>$p{wells});
    
    for (@wells) {
        $self->{BUTTONS}->{$_}->restore_default_style;
    }
    
}
sub clear_color {
    my $self = shift;    
    foreach my $dl_id (keys %{$self->{BUTTONS}}) {
      $self->{BUTTONS}->{$dl_id}->restore_default_style;
    }
}

=pod

=item register_well_handler

Registers a callback to be performed in repsonse to GTK events
processed by the buttons representing wells.

  my $id = $plate->register_well_handler(event_type=>'released',
                                         code=>\&code_ref,
                                         sectors=>['a1'],
                                         args=>['something1','something2'],
                                         return_well_info=>['well_name','dna_location']);


On a GTK event specified by event_type, the code reference 'code' will
be executed.  Arguments to this routine can be specified by including
them in the 'args' arrayref.

Optionally, information about the well will be appended to the
arguments if requested.  If the array referenced by 'return_well_info'
includes any of the following:

  'well_number'
  'well_name'
  'dna_location'

the appropriate data will be included in the argument vector, after
all previously specified arguments.  The data will also be appended in
the above order, regardless of the order in which the identifiers
appeared within return_well_info.

RETURN VALUE:

Returns an integer ID allowing you to refer to this handler later for
deregistering it via deregister_well_handler.

=cut

sub register_well_handler {
    my $self = shift;
    my %p = @_;
    

    # check for a few blatantly erroneous conditions
    die "PlateView error: no gtk event pased into register_well_handler" if (!defined $p{event_type});
    die "PlateView error: no coderef pased into register_well_handler" if (!defined $p{code});
    
    my @wells = $self->_aggregate_well_info(sectors=>$p{sectors},
                                            wells=>$p{wells});
    
    
    my %well_want;
    if (defined $p{return_well_info}) {
        %well_want = map {($_, 1)} @{$p{return_well_info}};
    }
    

    my $handlerid = $self->{HANDLER_REGID_COUNT} +=1;    

    my @gtk_handler_info;
    
    my $code = $p{code};


    # now start processing!
    for (@wells) {
        my $but = $self->{BUTTONS}->{$_};

        my @args = (defined $p{args} ? @{$p{args}} : ());
        
        push @args, $_ if (defined $well_want{'well_number'});
        push @args, $self->_well_number_to_well_name($_) if (defined $well_want{'well_name'});
        push @args, $self->_well_number_to_dna_location($_) if (defined $well_want{'dna_location'});
        
        
        # this closure represents the firing off of the actual event
        
        my $perform = sub {
            &$code(@args);
        };
        
        my $id = $but->signal_connect('released',
                                      $perform);
        
        push @gtk_handler_info, {button_id=>$_,
                                 gtk_handler_id=>$id};
                                      
    }

    $self->{BUTTON_HANDLERS}->{$handlerid} = \@gtk_handler_info;
    return $handlerid;
}

=pod

=item deregister_well_handler 

Deregisters a callback previously assigned to deregister_well_handler.


$plate->deregister_well_handler(id=>$id);


The 'id' parameter must be a previously defined integer ID returned by
register_well_handler.


=cut


sub deregister_well_handler {
    my $self = shift;
    my %p = @_;

    die "PlateView error: deregister_well_handler received no handler id" if (!defined $p{id});

    my $handlerid = $p{id};

    die "PlateView error: handler $handlerid not registered\n" if (!exists $self->{BUTTON_HANDLERS}->{$handlerid});
    
    
    for my $hid (@{$self->{BUTTON_HANDLERS}->{$handlerid}}) {
        $self->{BUTTONS}->{$hid->{button_id}}->signal_disconnect($hid->{gtk_handler_id});
    }

    delete $self->{BUTTON_HANDLERS}->{$handlerid};
}


=pod

=item set_well_tooltips

Assigns tool-tips to wells.  

A hash is passed into set_well_tooltips, wherein the keys are wells
and their corresponding values are the text to use as the tooltip.

The wells can be represented as either well numbers, well names, or
GSC::DNALocations.

=cut

sub set_well_tooltips {
    
    my $self = shift;
    
    my %msgs = @_;
    
    for (keys %msgs) {
        if (defined (my $k = $self->_identify_well($_))) {
            $self->{TOOLTIPS}->set_tip($self->{BUTTONS}->{$k}, $msgs{$_}, "");
        }
    }
}


#
# private fxn's, keep out!
#


# take in a whole set of sectors and wells (passed as well #'s, plate
# coordinates, or dna locations) and return the union of their well
# numbers for use internally

sub _aggregate_well_info {
    my $self = shift;
    
    my %p = @_;
    my %wells;
    
    # get the union of all sectors and wells fed in
    if (defined $p{sectors}) {
        for my $sec (@{$p{sectors}}) {
            %wells = map {($_,1)} $self->_identify_sectors($sec);
        }
    }
    
    if (defined $p{wells}) {
        for (@{$p{wells}}) {
            $wells{$self->_identify_well($_)} = 1;
        }
    }

    return keys %wells;
}


# given a DNALocation or a well name (i.e. h12), translate to the 
# well number (well 96)

sub _identify_well {
    
    my ($self, $well) = @_;
    
    if (ref($well) eq "GSC::DNALocation") {
        die "Plate type doesn't match DNA Location type " . $well->location_type . " ne " . $self->{PLATE_TYPE} if 
            ($well->location_type ne $self->{PLATE_TYPE});
        return $self->_well_name_to_well_number($well->location_name);

    } elsif ($well =~ m/[a-z]\d{1,2}/) {
        return $self->_well_name_to_well_number($well);
    }  else {
        return $well;
    }
}

sub _identify_sectors {
    my $self = shift;
    my $sector = shift;

    my $sec = GSC::Sector->get(sector_name=>$sector);
    
    my @dls = GSC::DNALocation->get(location_type=>$self->{PLATE_TYPE},
                                    sec_id=>$sec->id);

    return map {$self->_well_name_to_well_number($_->location_name)} @dls;
}

sub _well_name_to_well_number {
    my $self = shift;
    
    my $well_name = shift;
    
    $well_name =~ m/([a-z])(\d{1,2})/;
    
    my ($row, $col) = ($1, $2);

    my $well_num = (ord($row)-97) * $ROW_CONFIG->{$self->{PLATE_TYPE}}->{cols} + $col;
    
    return $well_num;
}

sub _well_number_to_well_name {
    my ($self, $well_number) = @_;

    my $col = $well_number % $ROW_CONFIG->{$self->{PLATE_TYPE}}->{cols};
    $col =  $ROW_CONFIG->{$self->{PLATE_TYPE}}->{cols} if ($col == 0);
    
    
    my $row = ($well_number - $col) / $ROW_CONFIG->{$self->{PLATE_TYPE}}->{cols};

    $col = "0" . $col if ($col < 10);

    return chr(ord('a') + $row) . "$col";
}

sub _well_number_to_dna_location {

    my ($self, $well_number) = @_;
    
    my $wn = $self->_well_number_to_well_name($well_number);

    if (my $dl = GSC::DNALocation->is_loaded(location_type=>$self->{PLATE_TYPE},
                                             location_name=>$wn)) {
        return $dl;
    } else {
        return GSC::DNALocation->get(location_type=>$self->{PLATE_TYPE},
                                     location_name=>$wn);
    }

}

1;
__END__

=pod

=back

=head1 BUGS

Report bugs to <software@watson.wustl.edu>

=head1 AUTHOR

ben oberkfell <boberkfe@watson.wustl.edu>

=cut

#$Header$
