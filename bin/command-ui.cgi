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

my $dispatch_url = $rurl;
$dispatch_url =~ s/-ui.cgi.*/-dispatch.cgi/;

my $html = html_form($delegate_class);
print "<html>\n\n",$html,"\n\n</html>";

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
        $text .= "<input type='submit' value='execute'>";
        $text .= "</form>\n";
        $text .= $sub_commands if $sub_commands;
        $text .= "</div>\n";

        $text .= "<b>results:</b>\n";
        $text .= "<pre id='results'>\n";
        $text .= "</pre>\n";
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

