package UR::DataSource::Pg;
use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::DataSource::PostgreSQL',
    is => ['UR::DataSource::RDBMS'],
    english_name => 'ur datasource postgresql',
    is_abstract => 1,
);

# RDBMS API

sub driver { "Pg" }

#sub server {
#    my $self = shift->_singleton_object();
#    $self->_init_database;
#    return $self->_database_file_path;
#}

sub owner { uc(shift->_singleton_object->login) }

#sub login {
#    undef
#}
#
#sub auth {
#    undef
#}

sub can_savepoint { 1;}

sub set_savepoint {
my($self,$sp_name) = @_;

    my $dbh = $self->get_default_dbh;
    $dbh->pg_savepoint($sp_name);
}


sub rollback_to_savepoint {
my($self,$sp_name) = @_;

    my $dbh = $self->get_default_dbh;
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
    my $dbh = $self->get_default_dbh;
    my($new_id) = $dbh->selectrow_array("SELECT nextval($sequence_name)");

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
    
    my $dbh = $self->get_default_dbh();
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



1;
