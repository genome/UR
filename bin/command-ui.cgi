#!/usr/local/bin/perl

use FindBin '$Bin';
use lib "$Bin/../lib";

# dispatch any modularized operation from an HTTP request

use Command;
use CGI;
use IO::File;
use File::Temp;

my $cgi = CGI->new();
print $cgi->header();

my $params = $cgi->Vars;
my $delegate_class = $params->{'@'};
delete $params->{'@'};

eval "use $delegate_class";
if ($@) {
    print "Failed to use class $delegate_class: $@";
    exit 1;
}

unless ($delegate_class->isa("Command")) {
    print "$delegate_class is not an implementation of Command.";
    exit;
}

my $rurl = $cgi->url();
my $base_url = $rurl;
$base_url =~ s/command-ui.cgi.*//;

$head.= <<EOS;
        <script language="javascript" type="text/javascript">

            function dispatch() { 

                function get_http_object() {
                    if (window.ActiveXObject)
                        return new ActiveXObject("Microsoft.XMLHTTP");
                    else if (window.XMLHttpRequest)
                        return new XMLHttpRequest();
                    else {
                        alert("Your browser does not support AJAX.");
                        return null;
                    }
                }

                httpr = get_http_object();

                function set_result() {
                    if(httpr.readyState == 4) {
                        document.getElementById('results').src = '$base_url/command-results.cgi?job_id=' + httpr.responseText;
                    }
                }

                if (httpr != null) {
                    httpr.open("GET", "$base_url/command-dispatch.cgi?\@=Command::Echo&in=111&out=222",true);
                    httpr.send(null);
                    httpr.onreadystatechange = set_result;
                }
            }

        </script>
    </head>
EOS

print "<html>\n",$head,"\n";

my $body = html_form($delegate_class);

print $body,"\n\n</html>";

sub html_form { 
    my $self = shift;

    my $command_name = $self->command_name;
    my $text;
    
    if (not $self->is_executable) {
        $text = "<div id='form'>\n<b>$command_name:</b><br>\n";
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

        $text = "<div id='form'>\n";
        $text .= "<form name='params' action='$dispatch_url' >\n";
        $text .= "<b>$command_name:</b><br>\n";
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
            $text .= "<input type='text' name='$param_name'/><br>\n"; 
        }
        $text .= "job id: <input id='job_id' type='hidden' name='job_id' value='/tmp/command-dispatch.13682.efIsm'/>\n";
        $text .= "<input type='button' onclick='javascript:dispatch();' value='execute'>";
        $text .= "</form>\n";
        $text .= $sub_commands if $sub_commands;
        $text .= "</div>\n";

        $text .= "<b>results:</b><br>\n";
        $text .= "<iframe id='results' width='100%', height='80%'/>\n";
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
            . ($sub->help_brief || '(undocumented)')
            . "<br>\n";
    }
    return $text;
}

