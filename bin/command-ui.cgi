#!/usr/local/bin/perl

use warnings;
use strict;


use FindBin '$Bin';
use lib "$Bin/../lib";

# dispatch any modularized operation from an HTTP request

my @missing_mods;
for my $mod (qw/Command CGI IO::File File::Temp JSON/) {
    eval "use $mod";
    if ($@) { push @missing_mods, [$mod,$@] }
}

my $cgi = CGI->new();
print $cgi->header();

if (@missing_mods) {
    print "<html>The following modules are missing on your system.  Please install them to use this tool.:<br>\n";
    for my $mod (@missing_mods) {
        print "    $mod<br>\n";
    }
    print "</html>";
}

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

                        var keyField2 = document.createElement('div');
                        keyField2.id = 'stderr';
                        keyField2.update("<pre>" + values['stderr'] + "</pre>");
                        \$('results').appendChild(keyField2);
                        
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

    my $command_name = $self->command_name;
    my $title_bar = '';
    my $link_class;
    my @words = split('::',$self->class);
    for my $word (@words[0..$#words-1]) {
        $link_class .= '::' if $link_class;
        $link_class .= $word;
        
        $title_bar .= ' ' if $title_bar;
        if ($link_class->isa('Command')) {
            $title_bar .= "<a href='http://google.com'>" . lc($word) . "</a>";
        }
        else {
            $title_bar .= $word;
        }
    }
    $title_bar .= ' ' . $words[-1];

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

        $text = "<div id='form-container'>\n";
        $text .= "<form name='params' id='form' action='$base_url/command-dispatch.cgi' >\n";
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
            . ($sub->help_brief || '(undocumented)')
            . "<br>\n";
    }
    return $text;
}

