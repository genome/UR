package UR::Namespace::Viewer::SchemaBrowser::CgiApp::Index;

use strict;
use warnings;

use base 'UR::Namespace::Viewer::SchemaBrowser::CgiApp::Base';


sub _template{q(
<HTML>
<HEAD><TITLE>Class/Schema Browser</TITLE></HEAD>
<BODY>
<A HREF="schema.html">Browse the Schema</A><BR>
<A HREF="class.html">Browse the Classes</A>
</BODY>
</HTML>
)};

1;
