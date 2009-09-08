package UR::Namespace::Viewer::SchemaBrowser::CgiApp::File;

use strict;
use warnings;

use base 'UR::Namespace::Viewer::SchemaBrowser::CgiApp::Base';

use IO::File;

sub setup {
my($self) = @_;
$DB::single=1;
    $self->start_mode('show_file');
    $self->mode_param('rm');
    $self->run_modes(
            'show_file' => 'show_file',
    );
}

sub show_file {
my $self = shift;
    my $file = $self->request->Env('filename');
    my $linenum = $self->request->Env('linenum');

    my $fh = IO::File->new($file);
    unless ( $fh ) {
        return "<HEAD><TITLE>File Browse Error</TITLE></HEAD><BODY>Can't open file $file: $!</BODY>";
    }

    my @data;
    my $lineno = 1;
    foreach my $line ( $fh->getlines() ) {
        chomp $line;
        push @data, { LINE => 'line'.$lineno++,
                      DATA => $line };
    }

    $self->tmpl->param(FILE_LINES => \@data);

    $self->tmpl->output();
}


sub _template{
q(
<HTML><HEAD><TITLE>File view</TITLE></HEAD>
<BODY>
<PRE>
<TMPL_LOOP NAME="FILE_LINES"><A NAME="<TMPL_VAR NAME="LINE">"><TMPL_VAR NAME="DATA"></A>
</TMPL_LOOP>
</PRE>





</BODY>
)};


1;
