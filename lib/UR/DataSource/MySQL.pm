package UR::DataSource::MySQL;
use strict;
use warnings;

require UR;
our $VERSION = "0.30"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::DataSource::MySQL',
    is => ['UR::DataSource::RDBMS'],
    english_name => 'ur datasource mysql',
    is_abstract => 1,
);

# RDBMS API

sub driver { "mysql" }

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

 
sub _sql_like_supports_escape { 0 };  # can't do an 'escape' clause with the 'like' operator

sub can_savepoint { 1;} 

sub _init_created_dbh
{
    my ($self, $dbh) = @_;
    return unless defined $dbh;

    my ($name, $value) = $dbh->selectrow_array("SHOW VARIABLES LIKE 'lower_case_table_names'");
    unless ($value == 1) {
        $self->warning_message("UR requires the mysqld server variable lower_case_table_names be set to 1 for case-insensitive table names in queries.  The current value is '$value'");
    }

    $dbh->{LongTruncOk} = 0;
    return $dbh;
}

sub _ignore_table {
    my $self = shift;
    my $table_name = shift;
    return 1 if $table_name =~ /^(pg_|sql_|URMETA)/;
}

#
# for concurrency's sake we need to use dummy tables in place of sequence generators here, too
#


sub _get_sequence_name_for_table_and_column {
    my $self = shift->_singleton_object;
    my ($table_name,$column_name) = @_;
    
    my $dbh = $self->get_default_dbh();
    
    # See if the sequence generator "table" is already there
    my $seq_table = sprintf('URMETA_%s_%s_SEQ', $table_name, $column_name);
    $DB::single = 1;
    unless ($self->{'_has_sequence_generator'}->{$seq_table} or
            grep {$_ eq $seq_table} $self->get_table_names() ) {
        unless ($dbh->do("CREATE TABLE IF NOT EXISTS $seq_table (next_value integer PRIMARY KEY AUTO_INCREMENT)")) {
            die "Failed to create sequence generator $seq_table: ".$dbh->errstr();
        }
    }
    $self->{'_has_sequence_generator'}->{$seq_table} = 1;

    return $seq_table;
}

sub _get_next_value_from_sequence {
    my($self,$sequence_name) = @_;

    my $dbh = $self->get_default_dbh();

    # FIXME can we use a statement handle with a wildcard as the table name here?
    unless ($dbh->do("INSERT into $sequence_name values(null)")) {
        die "Failed to INSERT into $sequence_name during id autogeneration: " . $dbh->errstr;
    }

    my $new_id = $dbh->last_insert_id(undef,undef,$sequence_name,'next_value');
    unless (defined $new_id) {
        die "last_insert_id() returned undef during id autogeneration after insert into $sequence_name: " . $dbh->errstr;
    }

    unless($dbh->do("DELETE from $sequence_name where next_value = $new_id")) {
        die "DELETE from $sequence_name for next_value $new_id failed during id autogeneration";
    }

    return $new_id;
}


sub get_bitmap_index_details_from_data_dictionary {
    # Mysql dosen't have bitmap indexes.
    return [];
}


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
    $dbh->do("rollback to savepoint $sp_name");
}

# FIXME This works on Mysql 4.x (and later?).  Mysql5 has a database called
# IMFORMATION_SCHEMA that may be more useful for these kinds of queries
sub get_unique_index_details_from_data_dictionary {
my($self,$table_name) = @_;

    my $dbh = $self->get_default_dbh();
    return undef unless $dbh;

    #$table_name = $dbh->quote($table_name);

    my $sql = qq(SHOW INDEX FROM $table_name);

    my $sth = $dbh->prepare($sql);
    return undef unless $sth;

    $sth->execute();

    my $ret;
    while (my $data = $sth->fetchrow_hashref()) {
        next if ($data->{'Non_unique'});
        $ret->{$data->{'Key_name'}} ||= [];
        push @{ $ret->{ $data->{'Key_name'} } }, $data->{'Column_name'};
    }

    return $ret;
}

sub get_column_details_from_data_dictionary {
    my $self = shift;

    # Mysql seems wierd about the distinction between catalog/database and schema/owner
    # For 'ur update classes', it works if we just pass in undef for catalog
    # The passed-in args are: $self,$catalog,$schema,$table,$column
    my $catalog = shift;

    return $self->SUPER::get_column_details_from_data_dictionary(undef, @_);
}

sub get_foreign_key_details_from_data_dictionary {
    my $self = shift;

    # Mysql requires undef in some fields instead of an empty string
    my @new_params = map { length($_) ? $_ : undef } @_;

    return $self->SUPER::get_foreign_key_details_from_data_dictionary(@new_params);
}


1;

=pod

=head1 NAME

UR::DataSource::MySQL - MySQL specific subclass of UR::DataSource::RDBMS

=head1 DESCRIPTION

This module provides the MySQL-specific methods necessary for interacting with
MySQL databases

=head1 SEE ALSO

L<UR::DataSource>, L<UR::DataSource::RDBMS>

=cut
