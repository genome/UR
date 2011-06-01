package UR::Doc::Writer::Html;

use strict;
use warnings;

use UR;
use UR::Doc::Section;
use UR::Doc::Pod2Html;
use Carp qw/croak/;

class UR::Doc::Writer::Html {
    is => 'UR::Doc::Writer',
    has => [
        title => { is => 'Text', },
        sections => {
            is => 'UR::Doc::Section',
            is_many => 1,
        },
    ]
};

sub render {
    my $self = shift;
    $self->content('');
    $self->_render_header;
    $self->_render_index;
    my $i = 0;
    for my $section ($self->sections) {
        $self->_render_section($section, $i++);
    }
    $self->_render_footer;
}

sub _render_header {
    my $self = shift;

    $self->_append("<h1><a name=\"___top\">" . $self->title . "</a></h1><hr/>\n");
}

sub _render_index {
    my $self = shift;
    my @titles = grep { /./ } map { $_->title } $self->sections;
    my $i = 0;
    if (@titles) {
        $self->_append("\n<ul>\n".
            join("\n", map {"<li><a href=\"#___sec".($i++)."\">$_</a></li>"} @titles)."</ul>\n\n");
    }
}

sub _render_section {
    my ($self, $section, $idx) = @_;
    if (my $title = $section->title) {
        $self->_append("<h1><a name=\"___sec$idx\" href=\"#___top\">$title</a></h1>\n");
    }
    my $content = $section->content;
    if ($section->format eq 'html') {
        $self->_append($content);
    } elsif ($section->format eq 'txt' or $section->format eq 'pod') {
        $content = "\n\n=pod\n\n$content\n\n=cut\n\n";
        my $new_content;
        my $translator = new UR::Doc::Pod2Html;
        $translator->output_string($new_content);
        $translator->parse_string_document($content);
        $self->_append($new_content);
    } else{
        croak "Unknown section type " . $section->type;
    }
    $self->_append("<br/>\n");
}

sub _render_footer {
    my $self = shift;
    $self->_append("</body></html>");
}

1;
