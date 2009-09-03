package UR::DataSource::RemoteCache;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::DataSource::RemoteCache',
    is => ['UR::DataSource'],
    english_name => 'ur datasource remotecache',
    properties => [
        host => {type => 'String', is_transient => 1},
        port => {type => 'String', is_transient => 1, default_value => 10293},
        socket => {type => 'IO::Socket', is_transient => 1},
    ],
    id_by => ['host','port'],
    doc => "A datasource representing a connection to another process",
);

# FIXME needs real pod docs.  In the mean time, here's how you'd create a program that just
# tells a class to get its data from some other server:
# use GSC;
# my $remote_ds = UR::DataSource::RemoteCache->create(host => 'localhost',port => 10293);
# my $class_object = UR::Object::Type->get(class_name => 'GSC::Clone');
# $class_object->data_source($remote_ds);
# @clones = GSC::Clone->get(10001);
# There's also a test case under the URT namespace

use IO::Socket;
use FreezeThaw;

sub create {
    my $class = shift;
    my %params = @_;

    my $obj = $class->SUPER::create(@_);

    return unless $obj;

    unless ($obj->_connect_socket()) {
        $class->error_message(sprintf("Failed to connect to remote host %s:%s",
                                      $params{'host'}, $params{'port'}));
        return;
    }

    return $obj;
}

    
sub get_name {
    my $self = shift;

    my $class_meta = $self->get_class_object;
    return sprintf("%s=%s:%s", $class_meta->class_name, $self->host, $self->port);
}

sub _connect_socket {
    my $self = shift;
    
    my $socket = IO::Socket::INET->new(PeerHost => $self->host,
                                       PeerPort => $self->port,
                                       ReuseAddr => 1,
                                       #ReusePort => 1,
                                     );
    unless ($socket) {
        $self->error_message("Couldn't connect to remote host: $!");
        return;
    }

    $self->socket($socket);

    $self->_init_created_socket();

    return 1;
}
                                       

sub _init_created_socket {
    # override in sub-classes
    1;
}


sub _remote_get_with_rule {
    my $self = shift;

    my $string = FreezeThaw::safeFreeze(\@_);
    my $socket = $self->socket;

    # First word is message length, second is command - 1 is "get"
    $socket->print(pack("LL", length($string),1),$string);

    my $cmd;
    ($string,$cmd) = $self->_read_message($socket);

    unless ($cmd == 129)  {
        $self->error_message("Got back unexpected command code.  Expected 129 got $cmd\n");
        return;
    }
      
    return unless ($string);  # An empty response
    
    my($result) = FreezeThaw::thaw($string);

    return @$result;
}


sub commit {
    $_[0]->_set_all_objects_saved_committed();
}

sub _sync_database {
    my $self = shift;
    my %params = @_;
    
    my $changed_objects = delete $params{changed_objects};
    my %objects_by_class_name;
    my %changed_object_classes_and_ids;
    for my $obj (@$changed_objects) {
        my $class_name = ref($obj);
        $objects_by_class_name{$class_name} ||= [];
        # UR::Context::_sync_databases passes us a list that has ghost
        # objects in the list twice.
        push(@{ $objects_by_class_name{$class_name} }, $obj) unless ($changed_object_classes_and_ids{$class_name}->{$obj->id}++);
    }

    my $socket = $self->socket();
    my $string = FreezeThaw::safeFreeze(\%objects_by_class_name);
    
    # Command 2 is sync_database
    $socket->print(pack("LL", length($string),2),$string);

    my $cmd;
    ($string,$cmd) = $self->_read_message($socket);

    unless ($cmd == 130) {
        $self->error_message("Got back unexpected command code.  Expected 130 got $cmd\n");
        return;
    }

    return unless ($string);
    my($result) = FreezeThaw::thaw($string);

    if ($result->[0]) {
        $self->_set_specified_objects_saved_uncommitted($changed_objects);
        return 1;
    } else {
        $self->error_message("Error propogated from server: ".$result->[1]);
        return 0;
    }
}

    
# This should be refactored into a messaging module later
sub _read_message {
    my $self = shift;
    my $socket = shift;

    my $buffer = "";
    my $read = $socket->sysread($buffer,8);
    if ($read == 0) {
        # The handle must be closed, or someone set it to non-blocking
        # and there's nothing to read
        return (undef, -1);
    }

    unless ($read == 8) {
        die "short read getting message length";
    }

    my($length,$cmd) = unpack("LL",$buffer);
    my $string = "";
    $read = $socket->sysread($string,$length);

    return($string,$cmd);
}
    


sub _get_template_data_for_loading {
    my ($self, $rule_template) = @_;
    my $template_data = $rule_template->{loading_data_cache};

    unless ($template_data) {
        my $class_name = $rule_template->subject_class_name;
        my $class_meta = $class_name->get_class_object;
        my $class_data = $self->_get_class_data_for_loading($class_meta);
    
        my $recursion_desc = $rule_template->recursion_desc;
        my $rule_template_without_recursion_desc = ($recursion_desc ? $rule_template->remove_filter('-recurse') : $rule_template);
        my $rule_template_specifies_value_for_subtype;
        my $sub_typing_property = $class_data->{'sub_typing_property'};
        if ($sub_typing_property) {
            $rule_template_specifies_value_for_subtype = $rule_template->specifies_value_for_property_name($sub_typing_property)
        }

        my @property_names = $class_name->property_names;

        $template_data = $rule_template->{loading_data_cache} = {
            select_clause                               => '',
            select_hint                                 => undef,
            from_clause                                 => '',
            where_clause                                => '',
            connect_by_clause                           => '',
            order_by_clause                             => '',

            needs_further_boolexpr_evaluation_after_loading => undef,
            loading_templates                           => [],

            sql_params                                  => [],
            filter_specs                                => [],
            property_names_in_resultset_order           => \@property_names,
            properties_for_params                       => [],

            rule_template_id                            => $rule_template->id,
            rule_template_without_recursion_desc        => $rule_template_without_recursion_desc,
            rule_template_id_without_recursion_desc     => $rule_template_without_recursion_desc->id,
            rule_matches_all                            => $rule_template->matches_all,
            rule_specifies_id                           => ($rule_template->specifies_value_for_property_name('id') || undef),
            rule_template_is_id_only                    => $rule_template->is_id_only,
            rule_template_specifies_value_for_subtype   => $rule_template_specifies_value_for_subtype,

            recursion_desc                              => undef,
            recurse_property_on_this_row                => undef,
            recurse_property_referencing_other_rows     => undef,

            %$class_data,
        };

    }
    return $template_data;
}



sub create_iterator_closure_for_rule {
    my ($self, $rule) = @_;

    # FIXME make this more efficient so that we dispatch the request, and the
    # iterator can fetch one item back at a time
    my @results = $self->_remote_get_with_rule($rule);

    # TODO Also, this is getting objects back, but is now expected to return an array of values.
    # Switch to sending a list of properties, getting a list of value arrays.
    my $loading_data = $self->_get_template_data_for_loading($rule->get_rule_template);
    my @names = @{ $loading_data->{property_names_in_resultset_order} };

    my $iterator = sub {
        return unless @results;
$DB::single=1;
        my $items_to_return = $_[0] || 1;
        my @return = 
            map { [ @$_{@names} ] } 
            splice(@results,0, $items_to_return);
        return @return;
    };

    return $iterator;
}



1;
