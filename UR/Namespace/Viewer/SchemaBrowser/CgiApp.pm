package UR::Namespace::Viewer::SchemaBrowser::CgiApp;

use strict;
use warnings;

UR::Object::Type->define(
    class_name => 'UR::Namespace::Viewer::SchemaBrowser::CgiApp',
    is => 'UR::Object::Viewer',
    properties => [
        http_server => {},
        port => { type => 'integer' },
        hostname => { type => 'string' },
        data_dir => { type => 'string' },
        timeout => { type => 'integer' },
    ],

);

use File::Temp;
use Sys::Hostname;
use Net::HTTPServer;

use Class::Autouse \&dynamically_load_page_class;

sub create {
my($class, %params) = @_;
$DB::single=1;
    my $port = delete $params{'port'};
    my $data_dir = delete $params{'data_dir'};
    my $sessions = delete $params{'sessions'};
    my $server_type = delete $params{'server_type'};
    my $timeout = delete $params{'timeout'};

    my $self = $class->SUPER::create(%params);

    $data_dir ||= File::Temp::tempdir('schemabrowserXXXXX', CLEANUP => 1);

    my $server = Net::HTTPServer->new( chroot => 1,
                                       datadir => $data_dir,
                                       docroot => undef,
                                       index => 'index.html',
                                       ssl => 0,
                                       port => $port || 'scan',
                                       sessions => $sessions || 0,
                                       type => $server_type || 'single',
                                     );

    unless ($server) {
        $self->error_message("Can't create HTTPServer object: $!");
        return;
    }

    $server->RegisterRegex('.*', sub { $self->render_page(@_) });

    $port = $server->Start();
    unless ($port) {
        $self->error_message("HTTPServer couldn't start: $!");
        return;
    }

    $self->port($port);
    $self->data_dir($data_dir);
    $self->hostname(hostname());
    $self->timeout($timeout);
    $self->http_server($server);

    return $self;
}



sub show {
my $self = shift;
    
$DB::single=1;
    my $server = $self->http_server;
    my $timeout = $self->timeout;

    our $LAST_PAGE_TIME = time();
    while($server->Process($timeout)) {
        last if ((time() - $LAST_PAGE_TIME) > $self->timeout);
    }

    $server->Stop();

    return 1;
}
    

sub render_page {
my $self = shift;
my $req = shift;
$DB::single=1;
    my $resp = $req->Response;

    our $LAST_PAGE_TIME = time;

    my($page) = ($req->Path =~ m/\/?(.*)\.html$/);
    $page ||= 'Index';
    $page = ucfirst $page;
    my $page_class = $self->get_class_object->class_name . '::' . $page;

    our %PAGE_OBJ_CACHE;
    my $page_obj = $PAGE_OBJ_CACHE{$page_class} ||= eval { $page_class->new(ur_namespace => $self->subject_class_name) };

    my $output;
    if ($page_obj) {
        $page_obj->request($req);
        $page_obj->response($resp);

        $output = $page_obj->run();
        $resp->Code(200);
    } else {
        $output = q(<TITLE>Object not found</TITLE><BODY><H1>Object not found!</H1>The URL you requested could not be translated to a valid module</BODY>);
        $resp->Code(404);
    }
    $resp->Print($output);

    return $resp;
}

# The classes that implement each page aren't UR-based classes, so we
# handle the autloading and subclassing of the namespace's page classes
# here
sub dynamically_load_page_class {
my($class_name, $method_name) = @_;
$DB::single=1;

    my @parts = split(/::/, $class_name);

    for (my $idx = @parts; $idx >= 0; $idx--) {
        my $parent_class = join('::',@parts[0 .. $idx-1]);
        my $page_class = join('::',@parts[$idx .. $#parts]);

        my $class_obj = eval {UR::Object::Type->get(class_name => $parent_class) };
        next unless $class_obj;
        
        if (grep {$_ eq __PACKAGE__} $class_obj->ordered_inherited_class_names) {
            my $isa_name = $parent_class . '::' . $page_class . '::ISA';
            my $schemabrowser_class_name = __PACKAGE__ . '::' . $page_class;
            no strict 'refs';
            push @{$isa_name}, $schemabrowser_class_name;
            # FIXME why dosen't require work here?
            eval "use $schemabrowser_class_name";
            last;
        }
    }
    my $ref = $class_name->can($method_name);
}
            
    
1;
