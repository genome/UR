use above 'UR';

use Data::Dumper;
use Test::More;
plan tests => 42;

&setup_files_and_classes();

foreach my $class_name ( qw( URT::Office URT::Office2 URT::Employee
                             URT::Employee2 URT::Employee3 URT::Employee4 )) {
    my $class_meta = UR::Object::Type->get($class_name);
    ok($class_meta, "Loaded class meta for $class_name");

    my @ds_name_parts = $class_name =~ m/^(\w+)::(.*)/;
    my $expected_ds_name = join('::', shift(@ds_name_parts), 'DataSource', @ds_name_parts);
    is($class_meta->{'data_source'}, $expected_ds_name, "It has a data source named");

#    my $ds_meta = UR::DataSource->get($class_meta->data_source);
#    ok($ds_meta, 'Loaded data source meta object');
};

# Try reading from the multi-file data source
my $an_office = URT::Office2->get(office_id => 1);
ok($an_office, 'Got office with id 1');
is($an_office->address, '123 Main St', 'Address is correct');


foreach my $emp_class ( qw( URT::Employee URT::Employee2 URT::Employee3 URT::Employee4 )) {
    my $employee = $emp_class->get(division => 'Europe', department => 'RnD', office_address => '345 Fake St');
    ok($employee, "Loaded a $emp_class employee by address (delegated property)");
    is($employee->emp_id, 5, 'emp_id is correct');
    is($employee->name, 'John', 'name is correct');
    is($employee->division, 'Europe', 'division is correct');
    is($employee->department, 'RnD', 'department is correct');
}


my $employee;
$employee = eval { URT::Employee->get(); };
ok(!$employee, 'Correctly could not URT::Employee->get() with no params');
like($@, qr/Can't resolve data source: no division specified in rule with id/, "Error message mentions 'division' property");

my $error_message;
UR::Context->message_callback('error', sub { $DB::single=1; $error_message = $_[0]->text });
$employee = eval { URT::Employee->get(division => 'NorthAmerica') };
ok(!$employee, 'Correctly could not URT::Employee->get() with only division');
like($@, qr/Can't resolve data source: no department specified in rule with id/, "Error message mentions 'department' property");
like($error_message, qr(Recursive entry.*URT::Employee), 'Error message did mention recursive call trapped');

my @employees = eval { URT::Employee->get(division => 'NorthAmerica', department => 'sales') };
ok(! scalar(@employees), 'URT::Employee->get() with non-existent department correctly returns no objects');
is($@, '', 'Correctly, no error message was generated');

my @employees = eval { URT::Employee->get(division => 'NorthAmerica', department => 'finance') };
is(scalar(@employees), 3, 'Loaded 3 employees from NorthAmerica/finance');


&cleanup();








sub setup_files_and_classes {

    mkdir "/tmp/inline_ds_$$";
    mkdir "/tmp/inline_ds_$$/NorthAmerica";
    mkdir "/tmp/inline_ds_$$/Europe";

    @office_data_files = ("/tmp/inline_ds_$$/offices.csv", "/tmp/inline_ds_$$/offices2.csv");
    our @files_to_remove_later = ( @office_data_files );
    
    # Fill in the data
    foreach my $name ( @office_data_files ) {
        my $f = IO::File->new(">$name");
        $f->print("1, 123 Main St\n");
        $f->print("4, 345 Fake St\n");
        $f->print("5, 1 Office Complex Ct\n");
        $f->print("100, One Hundred\n");
        $f->print("123, 123 Main St\n");
        $f->print("350, The Penthouse\n");
        $f->close();
    }
    # Yer basic datasource
    UR::Object::Type->define(
        class_name => 'URT::Office',
        id_by => [
            office_id => { is => 'Integer' },
        ],
        has => [
            address => { is => 'String' },
        ],
        data_source => {
            # This one fills in all the required info
            is => 'UR::DataSource::SortedCsvFile',
            file => $office_data_files[0],
            column_order => ['office_id', 'address'],
            sort_order => ['office_id'],
            skip_first_line => 0,
        },
    );
    # This one discovers columns and sort columns from the class data, and 
    # can read from a list of files
    UR::Object::Type->define(
        class_name => 'URT::Office2',
        id_by => [
            office_id => { is => 'Integer' },
        ],
        has => [
            address => { is => 'String' },
        ],
        data_source => {
            is => 'UR::DataSource::SortedCsvFile',
            file_list => \@office_data_files,   
        },
    );
 
    unshift @files_to_remove_later, &employee_file_resolver('NorthAmerica','finance');
    $f = IO::File->new(">$files_to_remove_later[0]");
    $f->print("1\tBob\t100\n");
    $f->print("2\tFred\t123\n");
    $f->print("3\tJoe\t350\n");
    $f->close();

    unshift @files_to_remove_later, &employee_file_resolver('Europe', 'RnD');
    $f = IO::File->new(">$files_to_remove_later[0]");
    $f->print("1\tMike\t1\n");
    $f->print("5\tJohn\t4\n");
    $f->print("6\tRick\t5\n");
    $f->close();
    # This one pivots between the two files create above with a function
    UR::Object::Type->define(
        class_name => 'URT::Employee',
        id_by => [
            'emp_id' => { is => 'Integer' },
        ],
        has => [
            name => { is => 'String' },
            office_id => { is => 'Integer' },
            office => { is => 'URT::Office', id_by => 'office_id' },
            office_address => { via => 'office', to => 'address' },
            division => { is => 'String' },
            department => { is => 'String' },
        ],
        data_source => {
            is => 'UR::DataSource::FileMux',
            delimiter => "\t",
            column_order => [ qw( emp_id name office_id ) ],
            sort_order   => [ 'emp_id' ],
            constant_values => ['division','department'],
            required_for_get => ['division', 'department'],
            resolve_path_with => \&employee_file_resolver,
        },
    );

    # This one is the same as above, but uses alternate syntax with 'resolve_path_with'
    UR::Object::Type->define(
        class_name => 'URT::Employee2',
        id_by => [
            'emp_id' => { is => 'Integer' },
        ],
        has => [
            name => { is => 'String' },
            office_id => { is => 'Integer' },
            office => { is => 'URT::Office', id_by => 'office_id' },
            office_address => { via => 'office', to => 'address' },
            division => { is => 'String' },
            department => { is => 'String' },
        ],
        data_source => {
            is => 'UR::DataSource::FileMux',
            delimiter => "\t",
            column_order => [ qw( emp_id name office_id ) ],
            sort_order   => [ 'emp_id' ],
            resolve_path_with => [\&employee_file_resolver, 'division', 'department'],
        },
    );

    # This one uses resolve_path_with with a base_path and list of properties
    UR::Object::Type->define(
        class_name => 'URT::Employee3',
        id_by => [
            'emp_id' => { is => 'Integer' },
        ],
        has => [
            name => { is => 'String' },
            office_id => { is => 'Integer' },
            office => { is => 'URT::Office', id_by => 'office_id' },
            office_address => { via => 'office', to => 'address' },
            division => { is => 'String' },
            department => { is => 'String' },
        ],
        data_source => {
            is => 'UR::DataSource::FileMux',
            delimiter => "\t",
            column_order => [ qw( emp_id name office_id ) ],
            sort_order   => [ 'emp_id' ],
            base_path => "/tmp/inline_ds_$$",
            resolve_path_with => ['division','department'],
       },
    );

    # This one uses resolve_path_with with an sprintf format
    UR::Object::Type->define(
        class_name => 'URT::Employee4',
        id_by => [
            'emp_id' => { is => 'Integer' },
        ],
        has => [
            name => { is => 'String' },
            office_id => { is => 'Integer' },
            office => { is => 'URT::Office', id_by => 'office_id' },
            office_address => { via => 'office', to => 'address' },
            division => { is => 'String' },
            department => { is => 'String' },
        ],
        data_source => {
            is => 'UR::DataSource::FileMux',
            delimiter => "\t",
            column_order => [ qw( emp_id name office_id ) ],
            sort_order   => [ 'emp_id' ],
            resolve_path_with => ["/tmp/inline_ds_$$/%s/%s", 'division','department'],
        },
    );
}

sub employee_file_resolver {
    my($division, $department) = @_;
    sprintf("/tmp/inline_ds_$$/$division/$department");
}


sub cleanup {
    my @files = glob("/tmp/inline_ds_$$/*/*");
    push @files, glob("/tmp/inline_ds_$$/*");

    foreach my $file ( @files ) {
        if (-d $file) {
            rmdir $file;
        } else {
            unlink $file;
        }
    }
}
