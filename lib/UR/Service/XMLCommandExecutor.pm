package UR::Service::XMLCommandExecutor;

use strict;
use warnings;

use UR;
our $VERSION = $UR::VERSION;

UR::Object::Type->define(
                          class_name => __PACKAGE__,
                          is         => 'UR::Object',
                          properties => [
                              host => { type => 'String', is_transient => 1, default_value => '0.0.0.0', doc => 'The local address to listen on' },
                              port => { type => 'String', is_transient => 1, default_value => 8080,      doc => 'The local port to listen on' },
                              server   => { type => 'Net::HTTPServer', is_transient => 1, doc           => 'The Net::HTTPServer instance for this Server instance' },
                              api_root => { type => 'String',          is_transient => 1, default_value => 'URapi' },
                          ],
                          id_by => [ 'host', 'port' ],
                          doc   => 'An object serving as a web server to respond to RPC requests via XML; wraps Net::HTTPServer',
);

=pod

=head1 NAME

UR::Service::XMLCommandExecutor - A self-contained RPC XML server for UR namespaces

=head1 SYNOPSIS

    use lib '/path/to/your/moduletree';
    use YourNamespace;

    my $rpc = UR::Service::XMLCommandExecutor->create(host => 'localhost',
                                                 port => '8080',
                                                 api_root => 'URapi',
                                                 docroot => '/html/pages/path',
                                               );
    $rpc->process();

=head1 Description

This is a class containing an implementation of a JSON-RPC server to respond to 
requests involving UR-based namespaces and their objects.  It uses Net::HTTPServer
as the web server back-end library.

Incoming requests are divided into two major categories:

=over 4

=item http://server:port/C<api-root>/class/Namespace/Class

This is the URL for a call to a class metnod on C<Namespace::Class>

=item http://server:port/C<api-root>/obj/Namespace/Class/id

This is the URL for a method call on an object of class Namespace::Class with the given id

=back

=head1 Constructor

The constructor takes the following named parameters:

=over 4

=item host

The hostname to listen on.  This can be an ip address, host name, or undef.
The default value is '0.0.0.0'.  This argument is passed along verbatim to
the Net::HTTPServer constructor.

=item port

The TCP port to listen on.  The default value is 8080.  This argument is passed
along verbatim to the Net::HTTPServer constructor.

=item api_root

The root path that the http server will listen for requests on.  The constructor registers
two paths with the Net::HTTPServer with RegisterRegex() for /C<api_root>/class/* and
/C<api_root>/obj/* to respond to class and instance metod calls.

=back

All other arguments are passed along to the Net::HTTPServer constructor.

=head1 Methods

=over 4

=item $rpc->process()

A wrapper to the Net::HTTPServer Process() method.  With no arguments, this call will
block forever from the perspective of the caller, and process all http requests coming in.
You can optionally pass in a timeout value in seconds, and it will respond to requests
for the given number of seconds before returning.

=back

=head1 Client Side

There are (or will be) client-side code in both Perl and Javascript.  The Perl code is (will be)
implemented as a UR::Context layer that will return light-weight object instances containing only
class info and IDs.  All method calls will be serialized and sent over the wire for the server
process to execute them.

The Javascript interface is defined in the file urinterface.js.  An example:

    var UR = new URInterface('http://localhost:8080/URApi/');  // Connect to the server
    var FooThingy = UR.get_class('Foo::Thingy');  // Get the class object for Foo::Thingy
    var thingy = FooThingy.get(1234);  // Retrieve an instance with ID 1234
    var result = thingy.call('method_name', 1, 2, 3);  // Call $thingy->method_name(1,2,3) on the server


=head1 SEE ALSO

Ney::HTTPServer, urinterface.js

=cut

use Net::HTTPServer;
use Class::Inspector;

use XML::Simple;
use XML::Dumper;
use Data::Dumper;
use FileHandle;

my $store_ids   = 0;
#my $class_ids = 0;

my %data_store;

sub create {
    my ( $class, %args ) = @_;

    my $api_root = delete $args{'api_root'};

    my $server = Net::HTTPServer->new(%args);
    return unless $server;

    my %create_args = ( host => $args{'host'}, port => $args{'port'} );
    $create_args{'api_root'} = $api_root if defined $api_root;
    my $self = $class->SUPER::create(%create_args);
    return unless $self;

    $self->server($server);

    #	$server->RegisterRegex("^/$api_root/class/*", sub { $self->_api_entry_classes(@_) } ) if $api_root;
    #	$server->RegisterRegex("^/$api_root/obj/*", sub { $self->_api_entry_obj(@_) } ) if $api_root;
    #	$server->RegisterRegex("^/$api_root/obj/*", sub { $self->_api_entry_classes(@_) } ) if $api_root;
    $server->RegisterRegex( "^/$api_root/class/*",				sub { $self->safe_process("_api_process", "class",		"na",	@_ ) } ) if $api_root;
    $server->RegisterRegex( "^/$api_root/obj/*",				sub { $self->safe_process("_api_process", "obj",		"na",	@_ ) } ) if $api_root;
    $server->RegisterRegex( "^/$api_root/act/*",				sub { $self->safe_process("_api_process", "act",		"na",	@_ ) } ) if $api_root;
    $server->RegisterRegex( "^/$api_root/store/*",				sub { $self->safe_process("_api_process ", "store",		"na",	@_ ) } ) if $api_root;
#    $server->RegisterRegex( "^/$api_root/store/internal/*",	sub { $self->_api_process( "internal",	"store",@_ ) } ) if $api_root;
#    $server->RegisterRegex( "^/$api_root/store/class/*",		sub { $self->_api_process( "class",		"store",@_ ) } ) if $api_root;
#    $server->RegisterRegex( "^/$api_root/store/obj/*",			sub { $self->_api_process( "obj",		"store",@_ ) } ) if $api_root;
#    $server->RegisterRegex( "^/$api_root/store/internal/*",	sub { $self->_api_process( "internal",	"store",@_ ) } ) if $api_root;
#    $server->RegisterRegex( "^/$api_root/command/refresh/*",	sub { $self->_store_process( "refresh", @_) } ) if $api_root;
#    $server->RegisterRegex( "^/$api_root/command/destroy/*",	sub { $self->_store_process( "destroy", @_) } ) if $api_root;
#    $server->RegisterRegex( "^/$api_root/command/dump/*",		sub { $self->_store_process( "dump", @_) } ) if $api_root;
    $server->RegisterRegex( "^/$api_root/command/",				sub { $self->safe_process("_store_process", @_ ) } ) if $api_root;
    $server->RegisterRegex( "^/$api_root/new/",					sub { $self->safe_process("_new_process", @_) } ) if $api_root;
    $server->RegisterRegex( "^/sources/*",						sub { $self->_dump_sources( @_ ) } );

    my $port = $server->Start();
    if ( $args{'port'} eq 'scan' ) {
        $self->port($port);
    }

    return $self;
}

sub safe_process {
    
    my $self = shift;
    my $sub = shift;
    
    my $rv;
    eval {
	$rv = $self->$sub(@_);
    };
    
    if ($@) {
	my $request = shift;
	$rv = $self->report_error($request,$@);
    }

    return $rv;
}

sub report_error {
    my $self = shift;
    my $request = shift;
    my $error_str = shift;

    my $response = $request->Response();
    $response->Header( "Content-Type", "text/plain" );
    $response->Print($error_str);
    return $response;
}

sub process {
    my $self = shift;

    &PrintMsg("Server is processing nao");

    #$self->server->Process(@_);
    my $server = $self->server;
    $server->Process(@_);
}

sub _api_process {
	$DB::single=1;
	
    my ( $self, $kind, $command, $request ) = @_;

	$self->_data_store_scrub();

    my $response = $request->Response();
    $response->Header( "Content-Type", "text/xml" );

    my $out = new XML::Dumper;
    $out->dtd;

    my $struct = $self->_parse_class_and_id_from_request( $request, $kind );

	if ($struct->{'error'}) {
		my $xml = $out->pl2xml($struct);
		$response->Print($xml);
		return $response;
	}

#    unless ($class) {
#        $response->code(404);
#        $response->Print( "Couldn't parse URL " . $request->URL );
#        return $response;
#    }
	
	my $class;
	my $store_id;

	my @retval;
    my $return_struct = { version => $struct->{'version'} };

    if ( $kind eq 'class' ) {
		   $class	= ${$struct}{'class'};
		my $method	= ${$struct}{'method'};
		my $params	= ${$struct}{'params'};
		
        {no warnings 'uninitialized'; &PrintMsg("Processing class '$class' '$method' '$params'");}
        if ( $method eq '_get_class_info' ) {    # called when the other end gets a class object
            eval {
                my $class_object = $class->__meta__;
                my %id_names     = map { $_ => 1 } $class_object->all_id_property_names();
                my @id_names     = keys(%id_names);

                my %property_names = map { $_ => 1 }
                  grep { !exists $id_names{$_} } $class_object->all_property_names();
                my @property_names = keys(%property_names);

                my $possible_method_names = Class::Inspector->methods( $class, 'public' );
                my @method_names = grep { !exists $id_names{$_} and !exists $property_names{$_} } @$possible_method_names;

                push @retval,
                  {
                    id_properties => \@id_names,
                    properties    => \@property_names,
                    methods       => \@method_names
                  };
            };
        } else {
            eval { @retval = $class->$method(@$params); };
        }

    } elsif ( $kind eq 'obj' ) {
		   $class	= ${$struct}{'class'};
        my $id		= ${$struct}{'id'};
		my $method	= ${$struct}{'method'};
		my $params	= ${$struct}{'params'};
		
		{no warnings 'uninitialized'; &PrintMsg("Processing obj '$class' '$method' '$id' '$params'");}
        eval {
            my $obj = $class->get($id);
            @retval = $obj->$method(@$params);
        };
		$return_struct->{'id'} = $struct->{'id'};
		
    } elsif ( $kind eq 'store' ) {
		   $class		= ${$struct}{'class'};
        my $life_span	= ${$struct}{'life_span'};
        my $id			= ${$struct}{'id'};

        &PrintMsg("Storing obj '$class' '$id' '$life_span'");
        eval {
            @retval = $class->get($id);
        };

		$store_id = $store_ids++;

        {no warnings 'uninitialized'; &PrintMsg("We're setting up store for id $store_id, life_span $life_span");}
		
		$return_struct->{'status'}			= "stored";
		$return_struct->{'life_span'}		= $life_span;
		$return_struct->{'store_id'}		= $store_id;
		
#		$data_store{$store_id} = {
#			life_span	=> $life_span,
#			description	=> "object for $class->get($id)",
#			data		=> "pending",
#			class		=> $class,
#			id			=> $id,
#			owner		=> "na"
#		};

		unless ($#retval == 0) {
			my %error;
			$error{'result'} = undef;
			$error{'error'} = "Your request returned ";
			$error{'error'} .= ($#retval > 0) ? "more than one object. " : "no objects. ";
			$error{'error'} .= "You may only store one object at a time.";
			my $xml = $out->pl2xml(\%error);
			$response->Print($xml);
			return $response;
		}

		$data_store{$store_id}->{'life_span'}	= $life_span;
		$data_store{$store_id}->{'description'}	= "object for $class->get($id)";

		### TAKE NOTE: this is the only $kind that assigns data in this if-else block
		###     All others go through the copying/un-blessing loop below
		###     (Of course, you don't want to unbless an object if it's going to be reused)
		$data_store{$store_id}->{'data'}		= $retval[0];
		$data_store{$store_id}->{'class'}		= $class;
		$data_store{$store_id}->{'id'}			= $id;
		$data_store{$store_id}->{'owner'}		= "na";
		
    } elsif ( $kind eq 'act' ) {
		my $store_id	= ${$struct}{'store_id'};
		my $method		= ${$struct}{'method'};
		my $params		= ${$struct}{'params'};
        &PrintMsg("Acting on stored obj '$store_id' '$method' '$params'");
		
		unless ($data_store{$store_id}) {
			$DB::single = 1;
			my %error;
			$error{'result'} = undef;
			$error{'error'} = "There is no data for the requsted store_id '$store_id'. ";
			$error{'error'} .= ($store_id >= $store_ids) ? "I'm pretty sure this id has not yet been allocated" : "This id was once allocated, but has probably time expired";
			my $xml = $out->pl2xml(\%error);
			$response->Print($xml);
			return $response;
		}
		
		my $obj			= $data_store{$store_id}{'data'};
		   $class		= $data_store{$store_id}{'class'};

		eval {
			@retval = $obj->$method(@$params);
		};

		#$description = "$data_store{$store_id}{description}; ->$method(@$params)";
	}


    if ($@) {
        $return_struct->{'result'} = undef;
        $return_struct->{'error'}  = $@;
    } else {
#        foreach my $item (@retval) {
#            my $reftype = ref $item;
#            if ( $reftype && $reftype ne 'ARRAY' && $reftype ne 'HASH' ) {    # If it's an object of some sort
#                my %copy = %$item;
#                $copy{'object_type'} = $class;
#                $item = \%copy;
#            }
#        }
        $return_struct->{'result'} = \@retval;
    }
	
    if ( $kind eq "store" ) {
#		$data_store{$store_id}->{'data'} = $return_struct->{'result'};
		##### LEFT OFF FIXING THIS
		##### STILL ENED TO FIX 'act' eval
#		$data_store{$store_id}{'data'} = $return_struct->{'result'};
    }

    my $xml = $out->pl2xml($return_struct);
	
#	my $xs = XML::Simple->new();
#	my $xml = $xs->XMLout($return_struct);

    $response->Print($xml);
	
    return $response;
}

sub _store_process {
    
    my ( $self, $request ) = @_;
    

	$self->_data_store_scrub();

    my $response = $request->Response();
    $response->Header( "Content-Type", "text/xml" );

    my $out = new XML::Dumper;
    $out->dtd;

	my $return_struct;	
	
    my $api_root = $self->api_root;
    my $url      = $request->URL();
    my $path     = &URLDecode( $request->Path() );
    my $query    = $request->Query();
    if ($query) { $query = $request->Query(); }

	&PrintMsg("Accessed '$url' by [na]");
	
    my @api_root  = split( /\//, $api_root );
    my @url_parts = split( /\//, $path );
    shift @url_parts until ( $url_parts[0] );

    {
        no warnings 'uninitialized';
        while ( $api_root[0] eq $url_parts[0] ) {
            shift @api_root;
            shift @url_parts;
        }
    }

    shift @url_parts if ( $url_parts[0] eq 'command' );

    my $command   = $url_parts[0];
    my $id        = $url_parts[1];
    my $parameter = $url_parts[2];

	unless ( ( ($command eq "destroy" || $command eq "dump") && $#url_parts == 1 ) || ( $command eq "refresh" && $#url_parts == 2 ) ) {
		&PrintMsg("Malformed command request");
	}

    if ( $command eq "dump" ) {
        &PrintMsg("Dumping $id");
		$return_struct->{'result'} = $data_store{$id}{'data'};
		$return_struct->{'life_remaining'} = ($data_store{$id}{'life_span'} - time);
		$return_struct->{'description'} = $data_store{$id}{'description'};	
		$return_struct->{'id'} = $id;
    } elsif ( $command eq "destroy" ) {
		$return_struct->{'result'} = "Destroyed";
        &PrintMsg("Destroying $id");
		$return_struct->{'description'} = $data_store{$id}{'description'};	
		$return_struct->{'id'} = $id;
		delete $data_store{$id};
    } elsif ( $command eq "refresh" ) {
        &PrintMsg("Refreshing '$id' with '$parameter'");
		$return_struct->{'result'} = "Refreshed";
		$data_store{$id}{'life_span'} = (time + $parameter);
		$return_struct->{'life_span'} = $data_store{$id}{'life_span'};
		$return_struct->{'life_remaining'} = ($data_store{$id}{'life_span'} - time);
		$return_struct->{'description'} = $data_store{$id}{'description'};	
		$return_struct->{'id'} = $id;
    }

    #	my @retval;

    #	my $xml = $out->pl2xml( $return_struct );
    #	$response->Print($xml);

    my $xml = $out->pl2xml($return_struct);

    $response->Print($xml);
    return $response;

#    $response->Print("Okay we did stuff like '$command'");
#    return $response;
}

sub _new_process {
    
    $DB::single = 1;
	my ($self, $request) = @_;
	
	my $response = $request->Response();

    my $api_root = $self->api_root;
    my $url      = $request->URL();
    my $path     = $request->Path();
    my $query    = $request->Query();

	&PrintMsg("Accessed '$url' by [na]");
	$DB::single=1;

	## Clean up the path portion
    my @api_root  = split( /\//, $api_root );
    my @url_parts = split( /\//, $path );
    shift @url_parts until ( $url_parts[0] );
	
    {
        no warnings 'uninitialized';
        while ( $api_root[0] eq $url_parts[0] ) {
            shift @api_root;
            shift @url_parts;
        }
    }
	shift @url_parts; # gets rid of the prefix

	my $is_xml = 0;
	my $is_html = 0;
	## Process the query portion
	my @query_parts	= split(/[&=]/, $query);
	for (my $i = 0 ; $i <= $#query_parts; $i += 2) {
		if ($query_parts[$i] =~ /style/i && $query_parts[$i+1] =~ /html/i) {
			$is_html = 1;
		}
		if ($query_parts[$i] =~ /style/i && $query_parts[$i+1] =~ /xml/i) {
			$is_xml = 1;
		}
		$query_parts[$i] = &URLDecode("--".$query_parts[$i]);
		$query_parts[$i+1] = &URLDecode($query_parts[$i+1]);
	}

	if ($is_xml) {
		$response->Header( "Content-Type", "text/xml" );
	} elsif ($is_html) {
		$response->Header( "Content-Type", "text/html" );
	} else {
		$response->Header( "Content-Type", "text/plain" );
	}

	## Process the path
	my $class = shift @url_parts;
	$class =~ s/(\w+)/\u\L$1/g; # capitalizes first letter of class
	$class .= "::Command"; # appends to the class name, eg Genome becomes Genome::Command
	# Not sure if this the proper way to determine this class
	
	$DB::single=1;

	my @param_list;
	push (@param_list, @url_parts);
	push (@param_list, @query_parts);

#	my @array = ("model","list","--show","user_name,name,id","--style","xml","--filter","name~bc%");

	my ($delegate_class, $params) = $class->resolve_class_and_params_for_argv(@param_list);

	$DB::single=1;
	#my $params={show=>"user_name,name,id",filter=>"name~bc%",style=>"xml"};

	my $command_object = $delegate_class->create(%$params);

	my $str;
	my $str_fh = IO::String->new($str);

	$DB::single=1;
	#my $old_fh = select($str_fh);
	$command_object->{'output'}=$str_fh;

	$command_object->execute($params);

	$DB::single=1;
	$response->Print($str);
	
	print "got to here";

	return $response;

}

sub _data_store_scrub {
	my $self = @_;

	my $currenttime = time;
	
	&PrintMsg("Checking data_store.");
	
	foreach my $id (keys %data_store) {
#		since delete apparently doesn't delete the key, too
		if (!$data_store{$id}){
			&PrintMsg("No $id; must've already been deleted.");
#			next;
		} else {
			my $itemtime = $data_store{$id}{'life_span'};
			if ($currenttime >$data_store{$id}{'life_span'}) {
				delete $data_store{$id};
				&PrintMsg("Deleted $id, which was ".($currenttime-$itemtime)." s expired.");
			} else {
				&PrintMsg("Kept $id, which will stay alive for ".($itemtime-$currenttime)." s longer.");
			}
		}
	}
}

sub _parse_class_and_id_from_request {
    my ( $self, $request, $kind ) = @_;

	my %call;

    my $api_root = $self->api_root;
    my $url      = $request->URL();
    my $path     = &URLDecode( $request->Path() );
    my $query    = $request->Query();

	&PrintMsg("Accessed '$url' by [na]");

	## Process the query portion
    if ($query) {
		$query = &URLDecode( $query );
		unless ($kind eq "class" || $kind eq "obj" || $kind eq "params") {
			return ErrorHash("Only class, obj, and act URLs may contain methods.  The kind of URL sent was '$kind'");
		}
		
		my @params_parts = split( /'(.+?)'[=&]/, $query );

		for ( my $i = 0 ; $i <= $#params_parts ; $i++ ) {
			if ( !$params_parts[$i] ) { splice( @params_parts, $i, 1 ); }
			elsif ( $params_parts[$i] =~ /^'(.+)'$/ ) { $params_parts[$i] = $1; }
			#		$params_parts[$i] =~ s/%20/ /g;
		}

		$call{'params'} = \@params_parts;
	}
	
	## Clean up the path portion
    my @api_root  = split( /\//, $api_root );
    my @url_parts = split( /\//, $path );
    shift @url_parts until ( $url_parts[0] );
	
    {
        no warnings 'uninitialized';
        while ( $api_root[0] eq $url_parts[0] ) {
            shift @api_root;
            shift @url_parts;
        }
    }

	## Do parsing and checks depending on the kind of path we're dealing with
	if ($kind eq "class") {
#		shift @url_parts if ( $url_parts[0] eq 'class' || $url_parts[0] eq 'obj' || $url_parts[0] eq 'store' );
		if ($#url_parts != 1) { return ErrorHash("Malformed URL for class; should be of form /Name::Space.method"); }

		my @method_split	= split( /\./, pop(@url_parts) );

		if ($#method_split != 1) { return ErrorHash("URL must contain /Name::Space.method as the last part of the path"); }
		$call{'class'}	= shift @method_split;
		$call{'method'}	= shift @method_split;

#		my @method_split = split( /\./, pop(@url_parts) );
#		push( @url_parts, shift @method_split );
#		my $method = shift @method_split;
		
	} elsif ($kind eq "obj") {
		if ($#url_parts != 2) { return ErrorHash("Malformed URL for obj; should be of form /Name::Space/id.method"); }
		
		my @method_split	= split( /\./, pop(@url_parts) );

		if ($#method_split != 1) { return ErrorHash("URL must contain /id.method as the last part of the path"); }
		$call{'id'}		= shift @method_split;
		$call{'method'}	= shift @method_split;

		$call{'class'}	= pop @url_parts;
		
		unless ( $call{'id'} =~ /^\d+$/ ) { return ErrorHash("Object ID must be a number"); }
		
	} elsif ($kind eq "store") {
		if ($#url_parts != 3) { return ErrorHash("Malformed URL for store; should be of form /store/###/Name::Space/id"); }
		
		$call{'life_span'}	= $url_parts[1] + time;
		$call{'class'}		= $url_parts[2]; 
		$call{'id'}			= $url_parts[3];
        
		unless ( $call{'id'} =~ /^\d+$/ ) { return ErrorHash("Object ID must be a number"); }
		unless ( $call{'life_span'} =~ /^\d+$/ ) { return ErrorHash("Lifespan must be number of seconds"); }
	
	} elsif ($kind eq "act") {
		if ($#url_parts != 1) { return ErrorHash("Malformed URL for act; should be of form /act/id.method?params"); }
		
		my @method_split	= split( /\./, pop(@url_parts) );
		$call{'store_id'}			= shift @method_split;
		$call{'method'}		= shift @method_split;

		unless ( $call{'store_id'} =~ /^\d+$/ ) { return ErrorHash("Store ID must be a number"); }

	} else { return ErrorHash("Got undefined kind '$kind' during URL parsing"); }
	
	#my $stay_alive;
	#my $is_store;
	#my $obj_store_id;
	#my $has_store_id;
	#my %call;

	#if ( $url_parts[0] eq 'store' ) {
	#    shift @url_parts;
	#    shift @url_parts if ( $url_parts[0] eq 'class' || $url_parts[0] eq 'obj' );
	#    $stay_alive = shift @url_parts;
	#    print $stay_alive;
	#    $is_store = 1;
	#    unless ( $stay_alive =~ /^\d+$/ ) {
	#        die "Oh snap. That needed to be in secs";
	#    }
	#    print "We are dealing with a store operation\n";
	#}

	#if ( $url_parts[0] eq 'retrieve' || $url_parts[0] eq 'act' || $url_parts[0] eq 'destroy' ) {
	#    shift @url_parts;
	#    shift @url_parts if ( $url_parts[0] eq 'class' || $url_parts[0] eq 'obj' );
	#    $obj_store_id = shift @url_parts;
	#    $has_store_id = 1;
	#    unless ( $stay_alive =~ /^\d+$/ ) {
	#        die "Oh snap. That needed to be an id";
	#    }
	#    print "We are dealing with a retrieve/act/destroy operation\n";
	#}

    #	my @params_parts = split(/(.+=.+)&/, $params);

	#$DB::single = 1;

	#$call{'class'}  = $class;
	#$call{'method'} = $method;
	#$call{'params'} = \@params_parts;

	#if ( $kind eq "obj" ) {
	#    my $id = pop @url_parts;
	#    $call{'id'} = $id;
	#} elsif ( $is_store == 1 ) {
	#    $call{'stay_alive'} = $stay_alive + time;
	#} elsif ( $has_store_id == 1 ) {
	#    $call{'store_id'} = $obj_store_id;
	#
	#    shift @url_parts;
	#}

    #else {
    #	die "major problems in the universe are occuring";
    #}

    return \%call;
}

sub _get_post_data_from_request {
    my ( $self, $request ) = @_;

    my $message = $request->Request;
    my ($data) = ( $message =~ m/\r\n\r\n(.*)/m );

    return $data;
}

sub URLDecode {
    my $theURL = $_[0];
    $theURL =~ tr/+/ /;
    $theURL =~ s/%([a-fA-F0-9]{2,2})/chr(hex($1))/eg;
    $theURL =~ s/<!--(.|\n)*-->//g;
    return $theURL;
}

sub ErrorHash {
	my $msg = shift;
	my %hash;
	$hash{'error'} = $msg;
	return \%hash;
}

sub PrintMsg {
    my $msg = shift;
    print "[".(localtime(time))."] [1m$msg[0m\n";
}

### This has been rolled into _api_process
###
#sub _api_entry_store_obj {
#    my ( $self, $request ) = @_;
#
#    my $response = $request->Response();
#
#    my $struct     = $self->_parse_class_and_id_from_request( $request, 1 );
#    my $class      = ${$struct}{'class'};
#    my $method     = ${$struct}{'method'};
#    my $id         = ${$struct}{'id'};
#    my $params     = ${$struct}{'params'};
#    my $life_span = ${$struct}{'life_span'};
#
#    unless ($class) {
#        $response->Code(404);
#        $response->Print( "Couldn't parse URL " . $request->URL );
#        return $response;
#    }
#
#       #my $method = $struct->{'method'};
#       #my $params = $struct->{'params'};
#
#    my @retval;
#    eval {
#        my $obj = $class->get($id);
#        @retval = $obj->$method(@$params);
#    };
#
#    my $return_struct = { id => $struct->{'id'}, version => $struct->{'version'} };
#    if ($@) {
#        $return_struct->{'result'} = undef;
#        $return_struct->{'error'}  = $@;
#    } else {
#        foreach my $item (@retval) {
#            my $reftype = ref $item;
#            if ( $reftype && $reftype ne 'ARRAY' && $reftype ne 'HASH' ) {    # If it's an object of some sort
#                my %copy = %$item;
#                $copy{'object_type'} = $class;
#                $item = \%copy;
#            }
#        }
#        $return_struct->{'result'} = \@retval;
#    }
#
#    my $store_id = $store_ids++;
#
#    $return_struct->{'status'}       = "success";
#    $return_struct->{'life_span'}   = $life_span;
#    $return_struct->{'obj_store_id'} = $store_id;
#
#    $data_store{$store_id} = $return_struct->{'result'};
#
#    my $out = new XML::Dumper;
#    $out->dtd;
#    my $xml = $out->pl2xml($return_struct);
#
#    $response->Print($xml);
#
#    return $response;
#}

### This has been simplified into _api_process
###
#sub _api_entry_classes {
#    my($self,$request) = @_;
#
#    my $response = $request->Response();
#    $DB::single = 1;
#	$response->Header("Content-Type", "text/xml");
#
#    my $struct = $self->_parse_class_and_id_from_request($request, 0);
#	my $class = ${$struct}{'class'};
#	my $method = ${$struct}{'method'};
#	#my %params = %{$struct{'params'}};
#	my $params = ${$struct}{'params'};
#
#    unless ($class) {
#        $response->Code(404);
#        $response->Print("Couldn't parse URL " . $request->URL);
#        return $response;
#    }
#
#    my @retval;
#
#    if ($method eq '_get_class_info') { # called when the other end gets a class object
#        eval {
#            my $class_object = $class->__meta__;
#            my %id_names = map { $_ => 1 } $class_object->all_id_property_names();
#            my @id_names = keys(%id_names);
#
#            my %property_names = map { $_ => 1 }
#                                 grep { ! exists $id_names{$_} }
#                                 $class_object->all_property_names();
#            my @property_names = keys(%property_names);
#
#            my $possible_method_names = Class::Inspector->methods($class, 'public');
#            my @method_names = grep { ! exists $id_names{$_} and ! exists $property_names{$_} }
#                               @$possible_method_names;
#
#            push @retval, { id_properties => \@id_names,
#                            properties => \@property_names,
#                            methods => \@method_names };
#        };
#    } else {
#		eval {
#		    @retval = $class->$method(@$params);
#		};
#    }
#
#    my $return_struct = { id => $struct->{'id'}, version => $struct->{'version'}, result => \@retval};
#    if ($@) {
#        $return_struct->{'result'} = undef;
#        $return_struct->{'error'} = $@;
#    } else {
#        foreach my $item ( @retval ) {
#            my $reftype = ref $item;
#            if ($reftype && $reftype ne 'ARRAY' && $reftype ne 'HASH') {  # If it's an object of some sort
#                my %copy = %$item;
#                $copy{'object_type'} = $class;
#                $item = \%copy;
#            }
#        }
#        $return_struct->{'result'} = \@retval;
#    }
#
#	my $out = new XML::Dumper;
#	$out->dtd;
#	my $xml = $out->pl2xml( $return_struct );
#
#
#	#my $xs = new XML::Simple;
#	#my $xml = $xs->XMLout(\@retval, noattr => 1);
#	#my $xml = $xs->XMLout($return_struct);
#
#	$response->Print($xml);
#
#    return $response;
#}

### This has been simplified into _api_process
###
#sub _api_entry_obj {
#    my ($self,$request) = @_;
#
#    my $response = $request->Response();
#
#    $DB::single = 1;
#
#    my $struct = $self->_parse_class_and_id_from_request($request, 1);
#	my $class = ${$struct}{'class'};
#	my $method = ${$struct}{'method'};
#	my $id = ${$struct}{'id'};
#	my $params = ${$struct}{'params'};
#
#
#
#    unless ($class) {
#        $response->Code(404);
#        $response->Print("Couldn't parse URL " . $request->URL);
#        return $response;
#    }
#
#   #my $method = $struct->{'method'};
#    #my $params = $struct->{'params'};
#
#    my @retval;
#    eval {
#        my $obj = $class->get($id);
#        @retval = $obj->$method(@$params);
#    };
#
#    my $return_struct = { id => $struct->{'id'}, version => $struct->{'version'}};
#    if ($@) {
#        $return_struct->{'result'} = undef;
#        $return_struct->{'error'} = $@;
#    } else {
#        foreach my $item ( @retval ) {
#            my $reftype = ref $item;
#            if ($reftype && $reftype ne 'ARRAY' && $reftype ne 'HASH') {  # If it's an object of some sort
#                my %copy = %$item;
#                $copy{'object_type'} = $class;
#                $item = \%copy;
#            }
#        }
#        $return_struct->{'result'} = \@retval;
#    }
#
#	my $out = new XML::Dumper;
#	$out->dtd;
#	my $xml = $out->pl2xml( $return_struct );
#
#	$response->Print($xml);
#
#    return $response;
#}

#sub _api_entry_store_class {
#	my($self,$request) = @_;
#
#	my $response = $request->Response();
#}

## This one uses the last part of the URL as the ID - won't work with a generic get()
#sub old_api_entry_point {
#    my($self,$request) = @_;
#
#    my $response = $request->Response();
#
#$DB::single=1;
#    my $data = $self->_get_post_data_from_request($request);
#    my $struct = decode_json($data);
#
#    my($class,$id) = $self->_parse_class_and_id_from_request($request);
#    unless ($class) {
#        $response->Code(404);
#        $response->Print("Couldn't parse URL " . $request->URL);
#        return $response;
#    }
#
#    my $method = $struct->{'method'};
#    my $params = $struct->{'params'};
#    my @retval;
#    eval {
#        my $obj = $class->get($id);
#        if ($method eq 'get') {
#            my %copy = %$obj;
#            $retval[0] = \%copy;
#        } else {
#            @retval = $obj->$method(@$params);
#        }
#    };
#
#    my $return_struct = { id => $struct->{'id'}, version => $struct->{'version'}};
#    if ($@) {
#        $return_struct->{'result'} = undef;
#        $return_struct->{'error'} = $@;
#    } else {
#        $return_struct->{'result'} = \@retval;
#    }
#
#
#    my $encoded_result = to_json($return_struct, {convert_blessed => 1});
#    $response->Print($encoded_result);
#
#    return $response;
#}

# URLs are expected to look something like this:
# http://server/URapi/Namespace::Class::Name/ID.method?'param1'='param2'&'param3'='param4'
# and would translate to the class Namespace::Class::Name with the ID property ID

1;

