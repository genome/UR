#!/gsc/bin/perl

use warnings;
use strict;

use CGI::Carp qw( fatalsToBrowser set_message );

use FindBin '$Bin';
#use lib "$Bin/../lib";
use lib qw(/gsc/scripts/lib/perl);

my @missing_mods;
for my $mod (qw/Command CGI IO::File File::Temp JSON XML::LibXML XML::LibXSLT/) {
    eval "use $mod";
    if ($@) {
		push @missing_mods, $mod;
	}
}

if (@missing_mods) {
	my $error_msg =  "The following modules are missing on your system. Please install them to use this tool.:\n";
	for my $mod (@missing_mods) {
		$error_msg .= "    $mod\n";
	}
	handle_errors($error_msg);
	exit 1;
}

# dispatch any modularized operation from an HTTP request

my $cgi = CGI->new();
print $cgi->header();

my $params = $cgi->Vars;
my $delegate_class = $params->{'@'};
delete $params->{'@'};

unless ($delegate_class) { $delegate_class = "Genome::Model::Command"; }

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
$base_url =~ s/command-ui.cgi.*//;

my $head.= <<EOS;
     <head>
        <script src="http://www.google.com/jsapi"></script>

        <script language="javascript" type="text/javascript">

            google.load('prototype', '1.6.1.0');
            google.load("scriptaculous", "1.8.2");

            function dispatch() {

                setStatus('sending request');
                \$('stderr_block').update('');
                \$('stdout_block').update('');
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
                switch (value) {
                  case 'succeeded':
                   \$('status').update(value);
                  break;

                  case 'crashed':
                    \$('status').update(value);
                  break;

                  case 'execution initiated':
                   \$('status').update('<img src="/resources/report_resources/apipe_dashboard/images/icons/spinner_24_FFFFFF.gif" width="16" height="16" align="absmiddle" class="spinner"/>' + value);
                  break;

                  case 'request sent':
                   \$('status').update('<img src="/resources/report_resources/apipe_dashboard/images/icons/spinner_24_FFFFFF.gif" width="16" height="16" align="absmiddle" class="spinner"/>' + value);
                  break;

                  default:
                    \$('status').update(value);
                  break;
                }
            }

            function updateTicker() {
                \$('ticker').update(\$('ticker').innerHTML + '.')
            }

            function requestResult(url) {
                new Ajax.Request(url, {
                    method: 'get',
                    onSuccess: function(response) {
                        var values = eval( '(' + response.responseText + ')' );
                        \$('stderr_block').update('');
                        \$('stdout_block').update('');

                        document.getElementById('status').update(values['status']);

                        var keyField = document.createElement('div');
                        keyField.id = 'stdout';
                        keyField.update(values['stdout']);
                        \$('stdout_block').appendChild(keyField);

                        if (values['stderr']) {
                            var keyField2 = document.createElement('div');
                            keyField2.id = 'stderr';
                            keyField2.update(values['stderr']);
                            \$('stderr_block').appendChild(keyField2);
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
<title>Web Dispatcher v0.1b</title>
<link rel="shortcut icon" href="/resources/report_resources/apipe_dashboard/images/gc_favicon.png" type="image/png">
<link rel="stylesheet" href="/resources/report_resources/apipe_dashboard/css/master.css" type="text/css" media="screen">
<link rel="stylesheet" href="/resources/report_resources/apipe_dashboard/css/webdispatcher.css" type="text/css" media="screen">
<link rel="stylesheet" href="/resources/report_resources/apipe_dashboard/css/tablesorter.css" type="text/css" media="screen">

    </head>
EOS

print "<html>\n",$head,"\n";

my $body = <<EOS;
<body><div class="container"><div class="background">
<div class="page_header"><table cellpadding="0" cellspacing="0" border="0"><tr>
<td><a href="status.cgi" alt="Go to Search Page" title="Go to Search Page"><img src="/resources/report_resources/apipe_dashboard/images/gc_header_logo2.png" width="44" height="45" align="absmiddle"></a></td>
<td><h1>Analysis Web Dispatcher v0.1b</h1></td>

</tr></table></div>
<div class="page_padding">
EOS

$body .= html_form($delegate_class);

$body .= <<EOS;
</div></div></div>
EOS

print $body,"\n\n</html>";

sub html_form {
    my $self = shift;

    my $command_name = $self->command_name;
    my $text;

	# generate title bar
    my $title_bar = '<h2 class="page_title">';
    my $link_class;
    my @words = split('::',$self->class);
    for my $word (@words) {
        $link_class .= '::' if $link_class;
        $link_class .= $word;

        $title_bar .= ' ' if $title_bar;
        eval "use $link_class";
        #TODO: split camel-case words into separate words for display
        if ($link_class->isa('Command')) {
            $title_bar .= "<a href='$base_url" . "command-ui.cgi?@=$link_class'>" . $word . "</a>";
        } else {
            $title_bar .= $word;
        }
    }
    $title_bar .= ":</h2>";
    if (my $help = $self->help_brief) {
        $title_bar .= "<p class='help'>" . $self->help_brief . "</p>";
    }

    unless ($self->is_executable) {
        $text = $title_bar;
        # no execute implemented
        if ($self->is_sub_command_delegator) {
            # show the list of sub-commands
			$text .= "<h3 class='sub_header'>sub commands:</h3>";
            $text .= sub_command_links_html($self);
        } else {
            # developer error
            my (@sub_command_dirs) = $self->sub_command_dirs;
            if (grep { -d $_ } @sub_command_dirs) {
                $text .= "No execute() implemented in $self, and no sub-commands found!<br>"
            } else {
                $text .= "No execute() implemented in $self, and no directory of sub-commands found!<br>"
            }
        }
        $text .= "</div>\n";
    } else {
        my $sub_commands = sub_command_links_html($self);
        my @args_meta = $self->_shell_args_property_meta();

        $text = "<div id='form-container'>\n";
        $text .= $title_bar;
        $text .= "<form name='params' id='form' action='$base_url" . "command-dispatch.cgi' >\n";
        $text .= "<input type='hidden' id='param-\@' name='\@' value='$delegate_class'>";
		$text .= '<table class="form">';

        for my $arg_meta (@args_meta) {

			$DB::single = 1;

            my $param_name      = $arg_meta->property_name;
            my $doc             = $arg_meta->doc;
            my $valid_values    = $arg_meta->valid_values;
            my $is_many         = $arg_meta->is_many;
            my $is_optional     = $arg_meta->is_optional;
            my $is_boolean      = $arg_meta->data_type eq 'Boolean' ? 1 : 0;

            my $param_label = $param_name;
            $param_label =~ s/_/ /g;

			my $row_class = ($is_optional) ? "optional" : "required";

			$text .= "<tr class='$row_class'><td class='label'>";
            $text .= ($is_optional) ? "$param_label:</td>" : "*$param_label:</td>";

			if ($is_boolean) {
				$text .= "<td class='value'><input type='checkbox' id='param-$param_name' name='$param_name' value='1'/></td>";
			} elsif (ref($valid_values) eq 'ARRAY') {
				$text .= "<td class='value'><select name='$param_name' id='param-$param_name'>";
				$text .= "<option value='' selected>None</option>";
				foreach (@$valid_values) {
					$text .= "<option value='$_'>$_</option>";
				}
				$text .= "</select></td>";
			} else {
				$text .= "<td class='value'><input type='text' id='param-$param_name' name='$param_name'/></td>";
			}
			$text .= "<td class='doc'>$doc</td></tr>";
        }
        $text .= "<tr><td></td><td class='button'><input type='button' onclick='javascript:dispatch();' value='execute'></td><td><div id='status'></div></td></tr>";
		$text .= "</table>";
        $text .= "</form>\n";
        $text .= "</div>";

		if ($sub_commands) {
			$text .= "<h3 class='sub_header'>sub commands:</h3>";
			$text .= $sub_commands;
		}

        #$text .= "<iframe id='results' width='100%', height='80%'/>\n";
        $text .= <<END_HTML;
<div id="ticker"></div>
    <div id="results">
      <div class="output_title"><h3>Results:</h3></div>
      <div id="stdout_block"></div>

      <div class="output_title"><h3>Warnings/Errors:</h3></div>
      <div id="stderr_block"></div></div>
END_HTML

    }

    return $text;
}

sub sub_command_links_html {
    my $self = shift;
    my $text = '<table class="commands">';
    my @sub = $self->sorted_sub_command_classes;
    for my $sub (@sub) {
        $text .= "<tr><td class='command'><a href='$base_url" . "command-ui.cgi?\@=$sub'>"
          . $sub->command_name_brief
            . '</a></td><td class="help">'
              . ($sub->help_brief || '(undocumented)')
                . "</td></tr>";
    }

    $text .= '</table>';
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
