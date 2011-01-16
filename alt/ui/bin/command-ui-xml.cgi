#!/usr/bin/env perl

use warnings;
use strict;


use FindBin '$Bin';
use lib "$Bin/../lib";

# dispatch any modularized operation from an HTTP request

my @missing_mods;
for my $mod (qw/Command CGI IO::File File::Temp JSON XML::LibXML XML::LibXSLT/) {
    eval "use $mod";
    if ($@) { push @missing_mods, $mod; }
}

use CGI::Carp qw( fatalsToBrowser set_message );

my $cgi = CGI->new();
print $cgi->header();

if (@missing_mods) {
  my $error_msg =  "The following modules are missing on your system. Please install them to use this tool.:\n";
  for my $mod (@missing_mods) {
    $error_msg .= "    $mod\n";
  }
  handle_errors($error_msg);
  exit 1;
}

my $params = $cgi->Vars;
my $delegate_class = $params->{'@'};
delete $params->{'@'};

eval "use $delegate_class";
if ($@) {
  handle_errors("Failed to use class $delegate_class: $@");
  exit 1;
}

unless ($delegate_class->isa("Command")) {
  handle_errors("$delegate_class is not an implementation of Command.");
  exit;
}

my $rurl = $cgi->url();
my $base_url = $rurl;
$base_url =~ s/\/command-ui.cgi.*//;

my $head.= <<EOS;
        <style type="text/css">
            #stdout {
                float:left;
                width:50%;
                font-size:10px;
                z:2;
            }
            #stderr {
                float:right;
                width:50%;
                font-weight:bold;
                z:1;
                color:red;
                background-color:yellow;
                opacity:.78;

            }
            #status {
                font-weight:bold;
                color:blue;
            }
            #ticker {
                font-weight:bold;
                color:blue;
            }
        </style>

        <script src="http://www.google.com/jsapi"></script>

        <script language="javascript" type="text/javascript">

            google.load('prototype', '1.6.1.0');
            google.load("scriptaculous", "1.8.2");

            function dispatch() {

                setStatus('sending request');
                \$('results').update('');
                \$( 'form').request({
                    onComplete: function(response) {
                        var url='$base_url/command-results.cgi?job_id=' + response.responseText;
                        setStatus('execution initiated');
                        requestResult(url);
                        //document.getElementById('results').src = '$base_url/command-results.cgi?job_id=' + response.responseText;
                    }
                });
                setStatus('request sent');
            }

            function setStatus(value) {
                \$('status').update(value)
            }

            function updateTicker() {
                \$('ticker').update(\$('ticker').innerHTML + '.')
            }

            function requestResult(url) {
                new Ajax.Request(url, {
                    method: 'get',
                    onSuccess: function(response) {
                        var values = eval( '(' + response.responseText + ')' );
                        \$('results').update('');

                        document.getElementById('status').update(values['status']);

                        var keyField = document.createElement('div');
                        keyField.id = 'stdout';
                        keyField.update("<pre>" + values['stdout'] + "</pre>");
                        \$('results').appendChild(keyField);

                        if (values['stderr']) {
                            var keyField2 = document.createElement('div');
                            keyField2.id = 'stderr';
                            keyField2.update("<pre>" + values['stderr'] + "</pre>");
                            \$('results').appendChild(keyField2);
                        }

                        new Effect.Highlight(\$('results'), {});
                        if (values['status'] == 'running') {
                            var fxn = "requestResult('" + url + "')";
                            setTimeout(fxn, 1000);
                            updateTicker();
                        } else {
                            \$('ticker').update();
                        }
                    }
                });
            }

        </script>

    </head>
EOS

print "<html>\n",$head,"\n";

my $body = html_form($delegate_class);

print $body,"\n\n</html>";

sub html_form {
    my $self = shift;

    my $title_bar = '<b>';
    my $link_class;
    my @words = split('::',$self->class);
    for my $word (@words[0..$#words-1]) {
        $link_class .= '::' if $link_class;
        $link_class .= $word;

        $title_bar .= ' ' if $title_bar;
        eval "use $link_class";
        next if $word eq 'Command';
        #TODO: split camel-case words into separate words for display
        if ($link_class->isa('Command')) {
            $title_bar .= "<a href='$base_url/command-ui.cgi?@=$link_class'>" . $word . "</a>";
        }
        else {
            $title_bar .= $word;
        }
    }
    $title_bar .= ' ' . $words[-1] . ':';
    $title_bar .= "</b><i><small>";
    if (my $help = $self->help_brief) {
        $title_bar .= "<br/>\n" . $self->help_brief . "\n";
    }
    $title_bar .= "</i></small>";


    my $text .= $title_bar;
    if (not $self->is_executable) {
        $text .= "<br/><div id='form'>\n";
        # no execute implemented
        if ($self->is_sub_command_delegator) {
            # show the list of sub-commands
            $text .= sub_command_links_html($self);
        }
        else {
            # developer error
            my (@sub_command_dirs) = $self->sub_command_dirs;
            if (grep { -d $_ } @sub_command_dirs) {
                $text .= "No execute() implemented in $self, and no sub-commands found!<br>"
            }
            else {
                $text .= "No execute() implemented in $self, and no directory of sub-commands found!<br>"
            }
        }
        $text .= "</div>\n";
    }
    else {
        my $sub_commands = sub_command_links_html($self);
        my @args_meta = $self->_shell_args_property_meta();

        $text .= "<p/><div id='form-container'>\n";
        $text .= "<form name='params' id='form' action='$base_url/command-dispatch.cgi' >\n";
        for my $arg_meta (@args_meta) {
            my $param_name      = $arg_meta->property_name;
            my $doc             = $arg_meta->doc;
            my $valid_values    = $arg_meta->valid_values;
            my $is_many         = $arg_meta->is_many;
            my $is_optional     = $arg_meta->is_optional;
            my $is_boolean      = $arg_meta->data_type eq 'Boolean' ? 1 : 0;

            my $param_label = $param_name;
            $param_label =~ s/_/ /g;

            $text .= "$param_label: ";
            $text .= "<input type='text' id='param-$param_name' name='$param_name'/><br>\n";
        }
        $text .= "<input type='hidden' id='param-\@' name='\@' value='$delegate_class'>";
        $text .= "<input type='button' onclick='javascript:dispatch();' value='execute'>";
        $text .= "</form>\n";
        $text .= $sub_commands if $sub_commands;
        $text .= "</div>\n";

        $text .= <<END_HTML;
    <span id="status"><br></span>
    <span id="ticker"></span><p/>
    <div id="results" style="border: 1px solid black; ">
    </div>
END_HTML
    }

    return $text;
}

sub sub_command_links_html {
    my $self = shift;
    my $text = '';
    my @sub = $self->sorted_sub_command_classes;
    for my $sub (@sub) {
        $text .= "<a href='$base_url/command-ui.cgi?\@=$sub'>"
            . $sub->command_name_brief
            . ' : '
            . '<small><i>' . ($sub->help_brief || '(undocumented)') . "</small></i></a>"
            . "<br>\n";
    }
    return $text;
}

sub transform_xml {
  my ($result, $xsl, $print_content_type) = @_;
  if ($print_content_type) {
    print "Content-Type: text/html; charset=ISO-8859-1\r\n\r\n";
  }

  $DB::single = 1;

  my $parser = XML::LibXML->new;
  my $xslt = XML::LibXSLT->new;
  my $source = $parser->parse_string($result);
  my $style_doc = $parser->parse_file($xsl);
  my $stylesheet = $xslt->parse_stylesheet($style_doc);

  my $results = $stylesheet->transform($source);
  print $stylesheet->output_string($results);

}

BEGIN {
  sub handle_errors {

    my $err = shift;
    my $doc = XML::LibXML->createDocument();
    my $error_node = $doc->createElement("error-msg");

    $error_node->addChild( $doc->createAttribute("error",$err) );

    $doc->setDocumentElement($error_node);
    my $result = $doc->toString(1);

    my $xsl = "xsl/error.xsl";

    transform_xml($result, $xsl, 0);
  }

  set_message(\&handle_errors);
}
