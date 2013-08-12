package URT::FakeDBI;

# A DBI-like test class we can force failures on

sub new {
    my $class = shift;
    return bless {prepare_count => 0, execute_count => 0}, $class;
}

sub configure {
    my $self = shift;
    my($key, $val) = @_;
    $self->{$key} = $val;
}

sub prepare {
    my $self = shift;
    $self->{prepare_count}++;
    if ($self->{prepare_fail}) {
        $self->set_errstr('prepare_fail');
        return undef;
    } else {
        return URT::FakeDBI::sth->new($self);
    }
}

sub set_errstr {
    my $self = shift;
    my $key = shift;
    $self->{errstr} = $self->{$key};
}

sub errstr {
    return shift->{errstr};
}

sub prepare_count {
    my $self = shift;
    if (@_) {
        $self->{prepare_count} = shift;
    }
    return $self->{prepare_count};
}
sub execute_count {
    my $self = shift;
    if (@_) {
        $self->{execute_count} = shift;
    }
    return $self->{execute_count};
}


package URT::FakeDBI::sth;

sub new {
    my $class = shift;
    my $dbh = shift;
    return bless \$dbh, $class;
}

sub execute {
    my $self = shift;
    my $dbh = $$self;
    $dbh->{execute_count}++;
    if ($dbh->{execute_fail}) {
        $dbh->set_errstr('execute_fail');
        return undef;
    } else {
        return 1;
    }
}

1;


