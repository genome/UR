package UR::DataSource::Pg;
use strict;
use warnings;

require UR;
our $VERSION = "0.38"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::DataSource::Pg',
    is => ['UR::DataSource::RDBMS'],
    is_abstract => 1,
);

# RDBMS API

sub driver { "Pg" }

#sub server {
#    my $self = shift->_singleton_object();
#    $self->_init_database;
#    return $self->_database_file_path;
#}

sub owner { shift->_singleton_object->login }

#sub login {
#    undef
#}
#
#sub auth {
#    undef
#}

our $BLOB_CHUNK_SIZE = 4096;  # Read/write this many bytes with each lo_read() and lo_write()

sub _default_sql_like_escape_string { return '\\\\' };

sub _format_sql_like_escape_string {
    my $class = shift;
    my $escape = shift;
    return "E'$escape'";
}

sub can_savepoint { 1;}

sub set_savepoint {
my($self,$sp_name) = @_;

    my $dbh = $self->get_default_handle;
    $dbh->pg_savepoint($sp_name);
}

sub rollback_to_savepoint {
my($self,$sp_name) = @_;

    my $dbh = $self->get_default_handle;
    $dbh->pg_rollback_to($sp_name);
}


sub _init_created_dbh
{
    my ($self, $dbh) = @_;
    return unless defined $dbh;
    $dbh->{LongTruncOk} = 0;
    return $dbh;
}

sub _ignore_table {
    my $self = shift;
    my $table_name = shift;
    return 1 if $table_name =~ /^(pg_|sql_)/;
}


sub _get_next_value_from_sequence {
my($self,$sequence_name) = @_;

    # we may need to change how this db handle is gotten
    my $dbh = $self->get_default_handle;
    my($new_id) = $dbh->selectrow_array("SELECT nextval('$sequence_name')");

    if ($dbh->err) {
        die "Failed to prepare SQL to generate a column id from sequence: $sequence_name.\n" . $dbh->errstr . "\n";
        return;
    }

    return $new_id;
}

# The default for PostgreSQL's serial datatype is to create a sequence called
# tablename_columnname_seq
sub _get_sequence_name_for_table_and_column {
my($self,$table_name, $column_name) = @_;
    return sprintf("%s_%s_seq",$table_name, $column_name);
}


sub get_bitmap_index_details_from_data_dictionary {
    # FIXME Postgres has bitmap indexes, but we don't support them yet.  See the Oracle
    # datasource module for details about how to get it working
    return [];
}


sub get_unique_index_details_from_data_dictionary {
my($self,$table_name) = @_;

    my $sql = qq(
        SELECT c_index.relname, a.attname
        FROM pg_catalog.pg_class c_table
        JOIN pg_catalog.pg_index i ON i.indrelid = c_table.oid
        JOIN pg_catalog.pg_class c_index ON c_index.oid = i.indexrelid
        JOIN pg_catalog.pg_attribute a ON a.attrelid = c_index.oid
        WHERE c_table.relname = ?
          and (i.indisunique = 't' or i.indisprimary = 't')
          and i.indisvalid = 't'
    );
    
    my $dbh = $self->get_default_handle();
    return undef unless $dbh;

    my $sth = $dbh->prepare($sql);
    return undef unless $sth;

    #my $db_owner = $self->owner();  # We should probably do something with the owner/schema
    $sth->execute($table_name);

    my $ret;
    while (my $data = $sth->fetchrow_hashref()) {
        $ret->{$data->{'relname'}} ||= [];
        push @{ $ret->{ $data->{'relname'} } }, $data->{'attname'};
    }

    return $ret;
}

my %ur_data_type_for_vendor_data_type = (
     # DB type      UR Type
     'SMALLINT'  => ['Integer', undef],
     'BIGINT'    => ['Integer', undef],
     'SERIAL'    => ['Integer', undef],

     'BYTEA'     => ['Blob', undef],

     'DOUBLE PRECISION' => ['Number', undef],
);
sub ur_data_type_for_data_source_data_type {
    my($class,$type) = @_;

    my $urtype = $ur_data_type_for_vendor_data_type{uc($type)};
    unless (defined $urtype) {
        $urtype = $class->SUPER::ur_data_type_for_data_source_data_type($type);
    }
    return $urtype;
}

sub _post_process_lob_values_for_select {
    my ($self, $dbh, $lob_id_arrayref) = @_;

    my $reader = sub {
        my $oid = shift;

        my $fh = $dbh->pg_lo_open($oid, $dbh->{pg_INV_READ});
        return undef unless $fh;

        my $buffer = '';
        my $chunk = '';
        # seems DBD::Pg doesn't have a way to get the LOB size ahead of time
        # read until we can't read any more
        eval {
            while ( my $len = $dbh->pg_lo_read($fh, $chunk, $BLOB_CHUNK_SIZE)) {
                unless (defined $len) {
                    die "BLOB read failed at offset " . length($buffer) . ': ' . $DBI::errstr;
                }
                $buffer .= $chunk;
            }
        };
        $dbh->pg_lo_close($fh);
        Carp::croak($@) if $@;  # rethrow the exception after closing

        return $buffer;
    };

    return map { $reader->($_) } @$lob_id_arrayref;
}


# Updating BLOBs in PostgreSQL
#
# PostgreSQL blobs are independant entities and need to be deleted
# explicitly each time a row that refers to them is deleted
# NOTE:  We're assumming here that each OID appears in the table
# data exactly one time!!
# If an OID appears as data in more than place, then the first row
# delete will delete the BLOB, leaving the others refering to nothing!
# Updates re-use the same OID, so they don't have the same problem deletes do

sub _resolve_blob_column_names_from_columns {
    my($self, $columns) = @_;

    return map { $_->column_name }
           grep { $_->data_type and ($_->data_type eq 'OID' or $_->data_type eq 'BLOB') }
           @$columns;
}

sub _prepare_sth_to_select_oid_values {
    my($self, $dbh, $table_ident, $where, @blob_column_names) = @_;

    my $sql = sprintf('SELECT %s FROM %s WHERE %s',
                        join(',', @blob_column_names),
                        $table_ident,
                        $where);
    my $sth = $dbh->prepare($sql);
    unless ($sth) {
        Carp::croak("Preparing select to retrieve oid columns failed for statement '$sql': $DBI::errstr");
    }
    return $sth;
}

sub _create_closure_to_update_blobs {
    my($self, $dbh, $table_ident, $where, $column_objects) = @_;

    my @blob_column_names = $self->resolve_blob_column_names_from_columns($column_objects);
    return unless @blob_column_names;

    my @blob_column_idx;
    for (my $n = 0; $n < @$column_objects; $n++) {
        my $this_column_data_type = $column_objects->[$n]->data_type;
        if ($this_column_data_type eq 'OID' or $this_column_data_type eq 'BLOB') {
            push(@blob_column_idx, $n);
        }
    }
    return unless @blob_column_idx;

    my $sth = $self->_prepare_sth_to_select_oid_values($dbh, $table_ident, $where, @blob_column_names);

    return sub {
        my($sth, $cmd) = @_;

        $sth->execute() || Carp::croak("Executing select to retrieve oid columns failed: $DBI::errstr");
        my $oids = $sth->fetchrow_arrayref();

        for (my $n = 0; $n < @blob_column_idx; $n++) {
            my $oid = $self->_save_oid($dbh, $oids->[$n], \{$cmd->{params}->[$n]});
            # After saving the data, put the OID into the data list that'll be saved
            # to the table's row
            $cmd->{params}->[$n] = $oid;
        }
    };
}


sub _create_closure_to_unlink_blobs {
    my($self, $dbh, $table_ident, $where, $columns) = @_;

    my @blob_column_names = $self->resolve_blob_column_names_from_columns($columns);
    return unless @blob_column_names;

    my $sth = $self->_prepare_sth_to_select_oid_values($dbh, $table_ident, $where, @blob_column_names);

    return sub {
        # my($sth, $cmd) = shift;  # unused for Pg
        $sth->execute() || Carp::croak("Executing select to retrieve oid columns failed: $DBI::errstr");
        my $oids = $sth->fetchrow_arrayref();
        foreach my $oid ( @$oids ) {
            $dbh->pg_lo_unlink($oid) || Carp::croak("pg_lo_unlink() failed for oid $oid when removing BLOBs for table $table_ident where $where");
        }
    };
}

# Returns a closure that accepts a statement handle
sub _create_closure_to_insert_blobs {
    my($self, $dbh, $table_ident, $where, $column_objects) = @_;

    my @blob_column_idx;
    for (my $n = 0; $n < @$column_objects; $n++) {
        my $this_column_data_type = $column_objects->[$n]->data_type;
        if ($this_column_data_type eq 'OID' or $this_column_data_type eq 'BLOB') {
            push(@blob_column_idx, $n);
        }
    }
    return unless @blob_column_idx;

    return sub {
        my($sth, $cmd) = @_;

        for (my $n = 0; $n < @blob_column_idx; $n++) {
            my $oid = $self->_save_oid($dbh, undef, \{$cmd->{params}->[$n]});
            # After saving the data, put the OID into the data list that'll be saved
            # to the table's row
            $cmd->{params}->[$n] = $oid;
        }
    };
}

# if $oid is undef, then create a new BLOB
sub _save_oid {
    my($self, $dbh, $oid, $dataref) = @_;

    unless (defined $oid) {
        $oid = $dbh->pg_lo_create($dbh->{pg_INV_WRITE});
    }
    return unless $oid;

    my $fh = $dbh->pg_lo_open($oid, $dbh->{pg_INV_WRITE});
    return unless $fh;

    my $written = 0;
    eval {
        while($written < length($$dataref)) {
            my $bytes = $dbh->pg_lo_write($fh, substr($$dataref, $written, $BLOB_CHUNK_SIZE), $BLOB_CHUNK_SIZE);
            unless (defined $bytes) {
                die "BLOB write failed at offset $written: $DBI::errstr";
            }
            $written += $bytes;
        }
    };
    $dbh->pg_lo_close($fh);
    Carp::croak($@) if $@;

    return $oid;
}

1;

=pod

=head1 NAME

UR::DataSource::Pg - PostgreSQL specific subclass of UR::DataSource::RDBMS

=head1 DESCRIPTION

This module provides the PostgreSQL-specific methods necessary for interacting with
PostgreSQL databases

=head1 SEE ALSO

L<UR::DataSource>, L<UR::DataSource::RDBMS>

=cut

