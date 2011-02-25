package UR::DataSource::Oracle;
use strict;
use warnings;

require UR;
our $VERSION = "0.29"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::DataSource::Oracle',
    is => ['UR::DataSource::RDBMS'],
    english_name => 'ur datasource oracle',
    is_abstract => 1,
);

sub driver { "Oracle" }

sub owner { uc(shift->_singleton_object->login) }

sub can_savepoint { 1 }  # Oracle supports savepoints inside transactions

sub set_savepoint {
my($self,$sp_name) = @_;

    my $dbh = $self->get_default_dbh;
    my $sp = $dbh->quote($sp_name);
    $dbh->do("savepoint $sp_name");
}


sub rollback_to_savepoint {
my($self,$sp_name) = @_;

    my $dbh = $self->get_default_dbh;
    my $sp = $dbh->quote($sp_name);
    $dbh->do("rollback to $sp_name");
}


sub _init_created_dbh {
    my ($self, $dbh) = @_;
    return unless defined $dbh;
    $dbh->{LongTruncOk} = 0;
    $dbh->do("alter session set NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS'");
    $dbh->do("alter session set NLS_TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS'");
    return $dbh;
}

sub _dbi_connect_args {
    my @args = shift->SUPER::_dbi_connect_args(@_);
    $args[3]{ora_module_name} = (UR::Context::Process->get_current->prog_name || $0);
    return @args;
}

sub _prepare_for_lob {
    { ora_auto_lob => 0 }
}

sub _post_process_lob_values {
    my ($self, $dbh, $lob_id_arrayref) = @_;
    return 
        map { 
            if (defined($_)) {
                my $length = $dbh->ora_lob_length($_);
                my $data = $dbh->ora_lob_read($_, 1, $length);
                # TODO: bind to a file for items of a certain size to save RAM.
                # Special work with tying a scalar to the file?
                $data;
            }
            else {
                undef;
            }
        } @$lob_id_arrayref;
}

sub _value_is_null {
    my ($class,$value) = @_;
    return 1 if not defined $value;
    return 1 if $value eq '';
    return 1 if (ref($value) eq 'HASH' and $value->{operator} eq '=' and (!defied($value->{value}) or $value->{value} eq ''));
    return 0;
}   

sub _ignore_table {
    my $self = shift;
    my $table_name = shift;
    return 1 if $table_name =~ /\$/;
}

sub get_table_last_ddl_times_by_table_name { 
    my $self = shift;
    my $sql =  qq|
        select object_name table_name, last_ddl_time
        from all_objects o        
        where o.owner = ?
        and (o.object_type = 'TABLE' or o.object_type = 'VIEW')
    |;
    my $data = $self->get_default_dbh->selectall_arrayref(
        $sql, 
        undef, 
        $self->owner
    );
    return { map { @$_ } @$data };
};

sub _get_next_value_from_sequence {
my($self,$sequence_name) = @_;

    # we may need to change how this db handle is gotten
    my $dbh = $self->get_default_dbh;
    my $new_id = $dbh->selectrow_array("SELECT " . $sequence_name . ".nextval from DUAL");

    if ($dbh->err) {
        die "Failed to prepare SQL to generate a column id from sequence: $sequence_name.\n" . $dbh->errstr . "\n";
        return;
    }

    return $new_id;
}

sub get_bitmap_index_details_from_data_dictionary {
my($self,$table_name) = @_;
    my $sql = qq(
        select c.table_name,c.column_name,c.index_name
        from all_indexes i join all_ind_columns c on i.index_name = c.index_name
        where i.index_type = 'BITMAP'
    );

    my @select_params;
    if ($table_name) {
        @select_params = $self->_resolve_owner_and_table_from_table_name($table_name);
        $sql .= " and i.table_owner = ? and i.table_name = ?";
    }

    my $dbh = $self->get_default_dbh;
    my $rows = $dbh->selectall_arrayref($sql, undef, @select_params);
    return undef unless $rows;
    
    my @ret = map { { table_name => $_->[0], column_name => $_->[1], index_name => $_->[2] } } @$rows;

    return \@ret;
}


sub get_unique_index_details_from_data_dictionary {
    my ($self,$table_name) = @_;
    my $sql = qq(
        select cc.constraint_name, cc.column_name
        from all_cons_columns cc
        join all_constraints c
        on c.constraint_name = cc.constraint_name
        and c.owner = cc.owner
        and c.constraint_type = 'U'
        where cc.table_name = ?
        and cc.owner = ?

        union

        select ai.index_name, aic.column_name
        from all_indexes ai
        join all_ind_columns aic
        on aic.index_name = ai.index_name
        and aic.index_owner = ai.owner
        where ai.uniqueness = 'UNIQUE'
        and aic.table_name = ?
        and aic.index_owner = ?
    );

    my $dbh = $self->get_default_dbh();
    return undef unless $dbh;

    my $sth = $dbh->prepare($sql);
    return undef unless $sth;

    my($db_owner,$dd_table_name) = $self->_resolve_owner_and_table_from_table_name($table_name);
    $sth->execute($table_name, $db_owner, $dd_table_name, $db_owner);

    my $ret;
    while (my $data = $sth->fetchrow_hashref()) {
        $ret->{$data->{'CONSTRAINT_NAME'}} ||= [];
        push @{ $ret->{ $data->{CONSTRAINT_NAME} } }, $data->{COLUMN_NAME};
    }

    return $ret;
}

sub set_userenv {

    # there are two places to set these oracle variables-
    # 1. this method in UR::DataSource::Oracle is a class method
    # that can be called to change the values later
    # 2. the method in YourSubclass::DataSource::Oracle is called in
    # _init_created_dbh which is called while the datasource
    # is still being set up- it operates directly on the db handle 

    my ($self, %p) = @_;

    my $dbh = $p{'dbh'} || $self->get_default_dbh();

    # module is application name
    my $module = $p{'module'} || $0;

    # storing username in 'action' oracle variable
    my $action = $p{'action'};
    if (! defined($action)) {
        $action = getpwuid($>); # real UID
    }

    die "Error setting userenv: module=$module action=$action" if (!$module or !$action);

    my $sql = q{BEGIN dbms_application_info.set_module(?, ?); END;};

    my $sth = $dbh->prepare($sql);
    if (!$sth) {
        warn "Couldnt prepare query to set module/action in Oracle";
        return undef;
    }

    $sth->execute($module, $action) || warn "Couldnt set module/action in Oracle";
}

sub get_userenv {

    # there are two ways to set these values but this is
    # the only way to retreive the values after they are set

    my ($self, $dbh) = @_;

    if (!$dbh) {
        $dbh = $self->get_default_dbh();
    }

    if (!$dbh) {
        warn "No dbh";
        return undef;
    }

    my $sql = q{
        SELECT sys_context('USERENV','MODULE') as module,
               sys_context('USERENV','ACTION') as action
          FROM dual
    };

    my $sth = $dbh->prepare($sql);
    return undef unless $sth;

    $sth->execute() || die "execute failed: $!";
    my $r = $sth->fetchrow_hashref();

    return $r;
}




1;

=pod

=head1 NAME

UR::DataSource::Oracle - Oracle specific subclass of UR::DataSource::RDBMS

=head1 DESCRIPTION

This module provides the Oracle-specific methods necessary for interacting with
Oracle databases

=head1 SEE ALSO

L<UR::DataSource>, L<UR::DataSource::RDBMS>

=cut

