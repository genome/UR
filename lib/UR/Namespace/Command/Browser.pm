package UR::Namespace::Command::Browser;

use strict;
use warnings;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => 'UR::Namespace::Command',
);


# This turns on the perl stuff to insert data in the DB
# namespace so we can get line numbers and stuff about
# loaded modules
BEGIN {
   unless ($^P) {
       no strict 'refs';
       *DB::DB = sub {};
       $^P = 0x31f;
   }
}

sub is_sub_command_delegator { 0;}


sub help_brief {
    "Start a web server to browse through the class and database structures.";
}


sub execute {
    my $self = shift;
    my $params = shift;
  
$DB::single=1;
    my $namespace = $self->namespace_name;
    # FIXME why dosen't require work here?
    eval "use  $namespace";
    if ($@) {
        $self->error_message("Failed to load module for $namespace: $@");
        return;
    }

    # FIXME This is a hack to preload all the default namespace's classes at startup
    # when the class metadata is in the SQLite DB, this won't be necessary anymore
    print "Preloading class information for namespace $namespace\n";
    $namespace->get_material_class_names;

    # FIXME the vocabulary converted "cgi app" into CgiApp, instead of CGIApp even though
    # I added CGI to the list of special cased words in GSC::Vocabulary.  It looks like
    # UR::Object::Viewer::create() is hard coded to use App::Vocabulary instead of whatever
    # the current namespace's vocabulary is
    my $v = $namespace->create_viewer(perspective => "schema browser", toolkit => "cgi app");

    printf("URL is http://%s:%d/\n",$v->hostname, $v->port);

    $v->timeout(600);

    $v->show();

}


    
1;
