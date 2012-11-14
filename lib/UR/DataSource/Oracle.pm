package UR::DataSource::Oracle;
use strict;
use warnings;

require UR;
our $VERSION = "0.38"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::DataSource::Oracle',
    is => ['UR::DataSource::RDBMS'],
    is_abstract => 1,
);

sub driver { "Oracle" }

sub owner { shift->_singleton_object->login }

sub can_savepoint { 1 }  # Oracle supports savepoints inside transactions

sub does_support_recursive_queries { 'connect by' };

sub set_savepoint {
my($self,$sp_name) = @_;

    my $dbh = $self->get_default_handle;
    my $sp = $dbh->quote($sp_name);
    $dbh->do("savepoint $sp_name");
}


sub rollback_to_savepoint {
my($self,$sp_name) = @_;

    my $dbh = $self->get_default_handle;
    my $sp = $dbh->quote($sp_name);
    $dbh->do("rollback to $sp_name");
}


sub _init_created_dbh {
    my ($self, $dbh) = @_;
    return unless defined $dbh;
    $dbh->{LongTruncOk} = 0;
    $dbh->do("alter session set NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS'");
    $dbh->do("alter session set NLS_TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SSXFF'");
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
    my $data = $self->get_default_handle->selectall_arrayref(
        $sql, 
        undef, 
        $self->owner
    );
    return { map { @$_ } @$data };
};

sub _get_next_value_from_sequence {
my($self,$sequence_name) = @_;

    # we may need to change how this db handle is gotten
    my $dbh = $self->get_default_handle;
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

    my $dbh = $self->get_default_handle;
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

    my $dbh = $self->get_default_handle();
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

    my $dbh = $p{'dbh'} || $self->get_default_handle();

    # module is application name
    my $module = $p{'module'} || $0;

    # storing username in 'action' oracle variable
    my $action = $p{'action'};
    if (! defined($action)) {
        $action = getpwuid($>); # real UID
    }

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
        $dbh = $self->get_default_handle();
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


my %ur_data_type_for_vendor_data_type = (
    'VARCHAR2'  => ['Text', undef],
    'BLOB'  => ['XmlBlob', undef],
);
sub ur_data_type_for_data_source_data_type {
    my($class,$type) = @_;

    my $urtype = $ur_data_type_for_vendor_data_type{uc($type)};
    unless (defined $urtype) {
        $urtype = $class->SUPER::ur_data_type_for_data_source_data_type($type);
    }
    return $urtype;
}

sub _alter_sth_for_selecting_blob_columns {
    my($self, $sth, $column_objects) = @_;

    for (my $n = 0; $n < @$column_objects; $n++) {
        next unless defined ($column_objects->[$n]);  # No metaDB info for this one
        if ($column_objects->[$n]->data_type eq 'BLOB') {
            $sth->bind_param($n+1, undef, { ora_type => 23 });
        }
    }
}

sub get_connection_debug_info {
    my $self = shift;
    my @debug_info = $self->SUPER::get_connection_debug_info(@_);
    push @debug_info, (
        "DBD::Oracle Version: ", $DBD::Oracle::VERSION, "\n",
        "TNS_ADMIN: ", $ENV{TNS_ADMIN}, "\n",
        "ORACLE_HOME: ", $ENV{ORACLE_HOME}, "\n",
    );
    return @debug_info;
}


# This is a near cut-and-paste from DBD::Oracle, with the exception that
# the query hint is removed, since it performs poorly on Oracle 11
sub get_foreign_key_details_from_data_dictionary {
    my $self = shift;

    my @version = split(/\./, $self->_get_oracle_server_version());
    if ($version[0] < '11') {
        return $self->SUPER::get_foreign_key_details_from_data_dictionary(@_);
    }

    my $attr = ( ref $_[0] eq 'HASH') ? $_[0] : {
        'UK_TABLE_SCHEM' => $_[1],'UK_TABLE_NAME ' => $_[2]
        ,'FK_TABLE_SCHEM' => $_[4],'FK_TABLE_NAME ' => $_[5] };
    my $SQL = <<'SQL';  # XXX: DEFERABILITY
SELECT *
  FROM
(
  SELECT
         to_char( NULL )    UK_TABLE_CAT
       , uk.OWNER           UK_TABLE_SCHEM
       , uk.TABLE_NAME      UK_TABLE_NAME
       , uc.COLUMN_NAME     UK_COLUMN_NAME
       , to_char( NULL )    FK_TABLE_CAT
       , fk.OWNER           FK_TABLE_SCHEM
       , fk.TABLE_NAME      FK_TABLE_NAME
       , fc.COLUMN_NAME     FK_COLUMN_NAME
       , uc.POSITION        ORDINAL_POSITION
       , 3                  UPDATE_RULE
       , decode( fk.DELETE_RULE, 'CASCADE', 0, 'RESTRICT', 1, 'SET NULL', 2, 'NO ACTION', 3, 'SET DEFAULT', 4 )
                            DELETE_RULE
       , fk.CONSTRAINT_NAME FK_NAME
       , uk.CONSTRAINT_NAME UK_NAME
       , to_char( NULL )    DEFERABILITY
       , decode( uk.CONSTRAINT_TYPE, 'P', 'PRIMARY', 'U', 'UNIQUE')
                            UNIQUE_OR_PRIMARY
    FROM ALL_CONSTRAINTS    uk
       , ALL_CONS_COLUMNS   uc
       , ALL_CONSTRAINTS    fk
       , ALL_CONS_COLUMNS   fc
   WHERE uk.OWNER            = uc.OWNER
     AND uk.CONSTRAINT_NAME  = uc.CONSTRAINT_NAME
     AND fk.OWNER            = fc.OWNER
     AND fk.CONSTRAINT_NAME  = fc.CONSTRAINT_NAME
     AND uk.CONSTRAINT_TYPE IN ('P','U')
     AND fk.CONSTRAINT_TYPE  = 'R'
     AND uk.CONSTRAINT_NAME  = fk.R_CONSTRAINT_NAME
     AND uk.OWNER            = fk.R_OWNER
     AND uc.POSITION         = fc.POSITION
)
 WHERE 1              = 1
SQL
    my @BindVals = ();
    while ( my ( $k, $v ) = each %$attr ) {
        if ( $v ) {
        $SQL .= "   AND $k = ?\n";
        push @BindVals, $v;
        }
    }
    $SQL .= " ORDER BY UK_TABLE_SCHEM, UK_TABLE_NAME, FK_TABLE_SCHEM, FK_TABLE_NAME, ORDINAL_POSITION\n";
    my $sth = $self->get_default_handle->prepare( $SQL ) or return undef;
    $sth->execute( @BindVals ) or return undef;
    $sth;
}


sub _get_oracle_server_version {
    my $self = shift;

    unless (exists $self->{'__ora_server_version'}) {
        my $dbh = $self->get_default_handle();
        my @data = $dbh->selectrow_arrayref('select version from v$instance');
        $self->{'__ora_server_version'} = $data[0]->[0];
    }
    return $self->{'__ora_server_version'};
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

