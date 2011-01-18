package UR::Object::Command::List;
use strict;
use warnings;

use IO::File;
use Data::Dumper;
require Term::ANSIColor;
use UR;
use UR::Object::Command::List::Style;

our $VERSION = "0.27"; # UR $VERSION;

class UR::Object::Command::List {
    is => 'Command',
    has => [
        subject_class => {
            is => 'UR::Object::Type', 
            id_by => 'subject_class_name',
        }, 
        filter => {
            is => 'Text',  
            is_optional => 1,
            doc => 'Filter results based on the parameters.  See below for how to.'
        },
        show => {
            is => 'Text',
            is_optional => 1,
            doc => 'Specify which columns to show, in order.' 
        },
        style => { 
            is => 'Text',
            is_optional => 1,
            default_value => 'text',
            doc => 'Style of the list: text (default), csv, pretty, html, xml',
        },
        csv_delimiter => {
           is => 'Text',
           is_optional => 1,
           default_value => ',',
           doc => 'For the csv output style, specify the field delimiter',
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
        _fields => {
            is_many => 1,
            is_optional => 1,
            doc => 'Methods which the caller intends to use on the fetched objects.  May lead to pre-fetching the data.'
        },
    ], 
    doc => 'lists objects matching specified params'
};


sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);
	$DB::single=1;

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

sub _resolve_boolexpr {
    my $self = shift;

    my ($bool_expr, %extra) = UR::BoolExpr->resolve_for_string(
        $self->subject_class_name, 
        $self->_complete_filter, 
        $self->_hint_string
    );

    $self->error_message( sprintf('Unrecognized field(s): %s', join(', ', keys %extra)) )
        and return if %extra;

    return $bool_expr;
}

sub execute {  
    my $self = shift;    
    
    $self->_validate_subject_class
        or return;

    my $bool_expr = $self->_resolve_boolexpr();
    return if not $bool_expr;
  
    # preloading the data ensures that the iterator doesn't trigger requery
    my @results = $self->subject_class_name->get($bool_expr);

    # TODO: remove the iterator entirely from the lister since all of the data is above--ss
    my $iterator;
    unless ($iterator = $self->subject_class_name->create_iterator(where => $bool_expr)) {
        $self->error_message($self->subject_class_name->error_message);
        return;
    }
   
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

    my $style_module_name = __PACKAGE__ . '::' . ucfirst $self->style;
    my $style_module = $style_module_name->new( 
        iterator => $iterator,
        show => $self->show,
        csv_delimiter => $self->csv_delimiter,
        noheaders => $self->noheaders,
        output => $self->output,
    );
    $style_module->format_and_print;

    return 1;
}

sub _filter_doc {          
    my $class = shift;

    my $doc = <<EOS;
Filtering:
----------
 Create filter equations by combining filterable properties with operators and
     values.
 Combine and separate these 'equations' by commas.  
 Use single quotes (') to contain values with spaces: name='genome center'
 Use percent signs (%) as wild cards in like (~).
 Use backslash or single quotes to escape characters which have special meaning
     to the shell such as < > and &

Operators:
----------
 =  (exactly equal to)
 ~  (like the value)
 :  (in the list of several values, slash "/" separated)
    (or between two values, dash "-" separated)
 >  (greater than)
 >= (greater than or equal to)
 <  (less than)
 <= (less than or equal to)

Examples:
---------
EOS
    if (my $help_synopsis = $class->help_synopsis) {
        $doc .= " $help_synopsis\n";
    } else {
        $doc .= <<EOS
 lister-command --filter name=Bob --show id,name,address
 lister-command --filter name='something with space',employees\>200,job~%manager
 lister-command --filter cost:20000-90000
 lister-command --filter answer:yes/maybe
EOS
    }

    $doc .= <<EOS;

Filterable Properties: 
----------------------
EOS

    # Try to get the subject class name
    my $self = $class->create;
    if ( not $self->subject_class_name 
            and my $subject_class_name = $self->_resolved_params_from_get_options->{subject_class_name} ) {
        $self = $class->create(subject_class_name => $subject_class_name);
    }

    if ( $self->subject_class_name ) {
        if ( my @properties = $self->_subject_class_filterable_properties ) {
            my $longest_name = 0;
            foreach my $property ( @properties ) {
                my $name_len = length($property->property_name);
                $longest_name = $name_len if ($name_len > $longest_name);
            }

            for my $property ( @properties ) {
                my $property_doc = $property->doc;
                unless ($property_doc) {
                    eval {
                        foreach my $ancestor_class_meta ( $property->class_meta->ancestry_class_metas ) {
                            my $ancestor_property_meta = $ancestor_class_meta->property_meta_for_name($property->property_name);
                            if ($ancestor_property_meta and $ancestor_property_meta->doc) {
                                $property_doc = $ancestor_property_meta->doc;
                                last;
                            }
                        }
                    };
                }
                $property_doc ||= ' (undocumented)';
                $property_doc =~ s/\n//gs;   # Get rid of embeded newlines

                my $data_type = $property->data_type || '';
                $data_type = ucfirst(lc $data_type);

                $doc .= sprintf(" %${longest_name}s  ($data_type): $property_doc\n",
                                $property->property_name);
            }
        }
        else {
            $doc .= sprintf(" %s\n", $self->error_message);
        }
    }
    else {
        $doc .= " Can't determine the list of filterable properties without a subject_class_name";
    }

    return $doc;
}

sub _validate_subject_class {
    my $self = shift;

    my $subject_class_name = $self->subject_class_name;
    $self->error_message("No subject_class_name indicated.")
        and return unless $subject_class_name;

    $self->error_message(
        sprintf(
            'This command is not designed to work on a base UR class (%s).',
            $subject_class_name,
        )
    )
        and return if $subject_class_name =~ /^UR::/;

    UR::Object::Type->use_module_with_namespace_constraints($subject_class_name);
    
    my $subject_class = $self->subject_class;
    $self->error_message(
        sprintf(
            'Can\'t get class meta object for class (%s).  Is this class a properly declared UR::Object?',
            $subject_class_name,
        )
    )
        and return unless $subject_class;
    
    $self->error_message(
        sprintf(
            'Can\'t find method (all_property_metas) in %s.  Is this a properly declared UR::Object class?',
            $subject_class_name,
        ) 
    )
        and return unless $subject_class->can('all_property_metas');

    return 1;
}

sub _subject_class_filterable_properties {
    my $self = shift;

    $self->_validate_subject_class
        or return;

    my %props = map { $_->property_name => $_ }
                    $self->subject_class->property_metas;

    return sort { $a->property_name cmp $b->property_name }
           grep { substr($_->property_name, 0, 1) ne '_' }  # Skip 'private' properties starting with '_'
           grep { ! $_->data_type or index($_->data_type, '::') == -1 }  # Can't filter object-type properties from a lister, right?
           values %props;
}

sub _base_filter {
    return;
}

sub _complete_filter {
    my $self = shift;
    return join(',', grep { defined $_ } $self->_base_filter,$self->filter);
}

sub help_detail {
    my $self = shift;
    return join(
        "\n",
        $self->_style_doc,
        $self->_filter_doc,
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
 xml - xml document using elements

EOS
}

sub valid_styles {
    return (qw/ text csv pretty html xml newtext/);
}

sub _hint_string {
    my $self = shift;
    return $self->show;
}


1;

