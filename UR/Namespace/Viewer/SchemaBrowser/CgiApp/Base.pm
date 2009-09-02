package UR::Namespace::Viewer::SchemaBrowser::CgiApp::Base;

# Since the classes that implement web pages have to be a subclass of
# CGI::Application, these are not UR-based classes, but more traditional
# Perl classes

use CGI;
use base 'CGI::Application';

use strict;
use warnings;

sub new {
my $class = shift;
my %params = @_;
$DB::single=1;

    my $ur_namespace = delete $params{'ur_namespace'};

    my $self = $class->SUPER::new(%params);

    my $template_data = $self->_template();
    if ($template_data) {
        my $tmpl = $self->load_tmpl(\$template_data,die_on_bad_params => 0,
                                                    cache => 0);
        $tmpl->param('CLASS' => $class);
        $self->tmpl($tmpl);
    }

    $self->run_modes('start' => '_default_render');
    $self->header_type('none');
    $self->ur_namespace($ur_namespace);

    return $self;
}


sub cgiapp_get_query {
my $self = shift;

    my $cgi = CGI->new($self->request->Query());
    return $cgi;
}

# create the basic accessors
our $PACKAGE = __PACKAGE__;
foreach my $acc_name ( 'request','response','tmpl', 'ur_namespace' ) {
    my $subref = sub {
                         my $self = shift;
                         if (@_) {
                             $self->{$PACKAGE}->{$acc_name} = shift;
                         } else {
                             $self->{$PACKAGE}->{$acc_name};
                         }
                     };
    no strict 'refs';
    *{$acc_name} = $subref;
}

sub namespace_name {
my $self = shift;
    return $self->request->Env('namespace') ||
           $self->ur_namespace ||
           '';
}

sub _default_render {
my $self = shift;

$DB::single=1;
    $self->tmpl->output();
}


sub run {
my $self = shift;

    my $buffer = "";
    my $fh;
    open ($fh, '>', \$buffer);

    my $old_fh = select $fh;
    my $output = $self->SUPER::run(@_);
    select $old_fh;

    return $buffer;
}


# FIXME is there a way to dynamically get all the available namespaces?
sub GetNamespaceNames {
return qw(GSC UR);
}



sub _template { q(
<HEAD><TITLE>Default Page</TITLE></HEAD>
<BODY>
<H2>You didn't specify a DATA section for class <TMPL_VAR NAME="CLASS"></H2>
</BODY>
)};


1;
