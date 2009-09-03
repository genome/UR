
package UR::Command::Test::Run;

#
# single dash command line params go to perl
# double dash command line params go to the script
#

use warnings;
use strict;
use File::Temp qw/tempdir/;
use Path::Class qw(file dir);
use DBI;
use Cwd;
use UR;

UR::Object::Type->define(
    class_name => __PACKAGE__,
    is => "UR::Command",
    has => [
        time    => { is => 'Boolean', doc => 'Write timelog sum to specified file', is_optional => 1 },
        long    => { is => 'Boolean', doc => 'Run tests including those flagged as long', is_optional => 1 },
        cover   => { is => 'List', doc => 'Cover only this(these) modules', is_optional => 1 },
        cover_svn_changes => { is_optional => 1, is => 'Boolean', doc => 'Cover modules modified in svn status' },
        cover_svk_changes => { is => 'Boolean', doc => 'Cover modules modified in svk status', is_optional => 1 },
        cover_cvs_changes => { is => 'Boolean', doc => 'Cover modules modified in cvs status', is_optional => 1 },
    ],
);

sub help_brief { "Run the test suite against the source tree." }

sub help_synopsis {
    return <<EOS
cd MyNamespace
ur test run                             # runs all tests in the t/ directory under pwd
ur test run t/mytest1.t t/mytest2.t     # run specific tests
ur test run -v -t --cover-svk-changes   # run tests to cover latest svk updates
EOS
}

sub help_detail {
    return <<EOS
This command is like "prove" or "make test", running the test suite for the current namespace.
EOS
}

sub execute {
    $DB::single = 1;
    my $self = shift;
    my $lib_path = $self->lib_path;
    my $working_path = $self->working_path;
    my @dirs = `find $working_path`;
    chomp @dirs;
    @dirs = grep { $_ =~ /\/t$/ and -d $_ } @dirs;
    if (@dirs == 0) {
        die "No 't' directories found!.  Write some tests...\n";
    }
    for my $dir (@dirs) {
        print "Running tests in $dir:\n";
        #my $cmd = "cd $parent;\nruntests -I $lib_path\n";
        #system $cmd;
        $self->_run_tests_in_dir_with_include_dir($dir,$lib_path);
    } 
}

sub _run_tests_in_dir_with_include_dir {
    my $self = shift;
    my $dir = shift;
    
    #my $parent = $dir;
    #$parent =~ s/\/t$//;

    my $lib_path = shift;
    my $argv = $self->bare_args; 
   
    # this ensures that we don't see warnings
    # and error statuses when doing the bulk test
    no warnings;
    local $ENV{UR_TEST_QUIET} = $ENV{UR_TEST_QUIET};
    unless (defined $ENV{UR_TEST_QUIET}) {
        $ENV{UR_TEST_QUIET} = 1;
    }
    use warnings;

    local $ENV{UR_DBI_NO_COMMIT} = 1;

    # the following 4 lines are the start of
    # some hackery (even moreso than this
    # script in the first place).  It continues
    # with the My::Test::Harness::Strap
    # definition later on
    use Test::Harness qw(&runtests $verbose);
    my $cb = $Test::Harness::Strap->{callback};
    $Test::Harness::Strap = My::Test::Harness::Straps->new;
    $Test::Harness::Strap->{callback} = $cb;
    
    $Test::Harness::Switches = "";
    
    my $perl_opts = '';
    my $script_opts = '';
    my @tests;
    my $timelog_sum = "";
    my $timelog_dir = "";
    my $ps;     # does this look like a perl or script option

    my $v = $self->verbose || 0;
    my $t = $self->time;
    if ($t) {
        $timelog_sum = file($t);
        $timelog_dir = dir(tempdir());
    }   

    if($self->long) {
        # Make sure long tests run
        $ENV{GSCAPP_RUN_LONG_TESTS}=1;
    }

    my @cover_specific_modules;
    
    if (my $cover = $self->cover) {
        push @cover_specific_modules, @$cover;
    }

    if ($self->cover_svn_changes) {
        push @cover_specific_modules, get_status_file_list('svn');
    }
    elsif ($self->cover_svk_changes) {
        push @cover_specific_modules, get_status_file_list('svk');
    }
    elsif ($self->cover_cvs_changes) {
        push @cover_specific_modules, get_status_file_list('cvs');
    }

    # nasty parsing of command line args
    for (my $n = 0; $n < @$argv; $n++) {
        $_ = $argv->[$n];
        
        if (/^-/) {
            if (/^--/) {
                $script_opts .= "$_ ";
                $ps = 's';
            }
            else {
                $perl_opts .= "$_ ";
                $ps = 'p';
            }
        }
        elsif (/\.t$/ or /^t\//) {
            push @tests, $_;
        }
        elsif($ps eq 's') {
            $script_opts .= "$_ ";
        }
        else {
            $perl_opts .= "$_ ";
        }
    }
    
    if (@cover_specific_modules) {
        my $dbh = DBI->connect("dbi:SQLite:/gsc/var/cache/testsuite/coverage_metrics.sqlitedb","","");
        $dbh->{PrintError} = 0;
        $dbh->{RaiseError} = 1;
        my %tests_covering_specified_modules;
        for my $module_name (@cover_specific_modules) {
            my $module_test_names = $dbh->selectcol_arrayref(
                "select test_name from test_module_use where module_name = ?",undef,$module_name
            );
            for my $test_name (@$module_test_names) {
                $tests_covering_specified_modules{$test_name} ||= [];
                push @{ $tests_covering_specified_modules{$test_name} }, $module_name;
            }
        }
        
        if (@tests) {
            # specific tests were listed: only run the intersection of that set and the covering set
            my @filtered_tests;
            for my $test_name (sort keys %tests_covering_specified_modules) {
                my $specified_modules_coverted = $tests_covering_specified_modules{$test_name};
                $test_name =~ s/^(.*?)(\/t\/.*)$/$2/g;
                if (my @matches = grep { $test_name =~ $_ } @tests) {
                    if (@matches > 1) {
                        Carp::confess("test $test_name matches multiple items in the tests on the filesystem: @matches");
                    }
                    elsif (@matches == 0) {
                        Carp::confess("test $test_name matches nothing in the tests on the filesystem!");
                    }
                    else {
                        print STDERR "Running $matches[0] for modules @$specified_modules_coverted.\n";
                        push @filtered_tests, $matches[0];
                    }
                }
            }
            @tests = @filtered_tests;
        }
        else {
            # no tests explicitly specified on the command line: run exactly those which cover the listed modules
            @tests = sort keys %tests_covering_specified_modules;
        }
        print "Running the " . scalar(@tests) . " tests which load the specified modules.\n";
    }
    else {
        if (@tests) {
            # use the specified list
        }
        else {
            # use all in the current t directory
            @tests = glob("$dir/*.t");
        }
    }

    use Cwd;
    my $cwd = cwd();
    for (@tests) {
        s/^$cwd\///;
    }
    
    # turn on no-commit
    #$script_opts .= ' --no-commit'
    #    unless ($script_opts =~ /\-\-no\-commit/);
    
    #my $cmd = "PERL_DL_NONLAZY=1 /gsc/bin/perl $perl_opts";
    #$cmd .= q{  -e 'use Test::Harness qw(&runtests $verbose); $verbose=} . $v . q{; runtests @ARGV;' } . $tests;
    #print "$cmd\n";
    #exec($cmd);
    
    $verbose = $v;

    local $My::Test::Harness::Straps::timelog_dir   = $timelog_dir;
    local $My::Test::Harness::Straps::timelog_sum   = $timelog_sum;
    local $My::Test::Harness::Straps::perl_opts     = $perl_opts;
    local $My::Test::Harness::Straps::script_opts   = $script_opts;
    local $My::Test::Harness::Straps::v             = $v;
    runtests(@tests);
}


sub get_status_file_list {
    my $tool = shift;

    my @status_data = eval {

        my $orig_cwd = cwd();
        my @words = grep { length($_) } split("/",$orig_cwd);
        while (@words and ($words[-1] ne "GSC")) {
            pop @words;
        }
        unless (@words and $words[-1] eq "GSC") {
            die "Cannot find 'GSC' directory above the cwd.  Cannot auto-run $tool status.\n";
        }
        pop @words;
        my $vcs_dir = "/" . join("/", @words);

        unless (chdir($vcs_dir)) {
            die "Failed to change directories to $vcs_dir!";
        }

        my @lines;
        if ($tool eq "svn" or $tool eq "svk") {
            @lines = IO::File->new("$tool status |")->getlines;
        }
        elsif ($tool eq "cvs") {
            @lines = IO::File->new("cvs -q up |")->getlines;
        }
        else {
            die "Unknown tool $tool.  Try svn, svk, or cvs.\n";
        }

        unless (chdir($orig_cwd)) {
            die "Error changing directory back to the original cwd after checking file status with $tool.";
        }

        return @lines;
    };

    if ($@) {
        die "Error checking version control status for $tool:\n$@";
    }

    my @modules;
    for my $line (@status_data) {
        my ($status,$file) = ($line =~ /^(.).\s*(\S+)/);
        next if $status eq "?" or $status eq "!";
        print "covering $file\n";
        push @modules, $file;
    }

    unless (@modules) {
        die "Failed to find modified modules via $tool.\n";
    }

    return @modules;
}


# continuation of hackery from above
package My::Test::Harness::Straps;

use base 'Test::Harness::Straps';
use Path::Class qw(file dir);

# We used-to override analyze_file, which we copied into the subclass and modified.
# Now that method calls _command_line() which is all we need to override.

# NOTE: $perl_opts, $script_opts, $v and $timelog_dir
# are defined above and are part of the method override below.

our $perl_opts;
our $script_opts;
our $v;
our $timelog_dir;
our $timelog_sum;

sub _command_line {
    my $self = shift;
    my $file = shift;

    my $command =  $self->_command();
    my $switches = $self->_switches($file);

    $file = qq["$file"] if ($file =~ /\s/) && ($file !~ /^".*"$/);

    # modified from original
    my $line = "$command $perl_opts $switches $file $script_opts";

    # addition to original
    print " $line ...\n" if $v;

    # addition to original
    if ($timelog_dir) {
        my $timelog_file = file($file)->basename;
        $timelog_file =~ s/\.t$/.time/;
        unless (-d $timelog_dir) {
            mkdir $timelog_dir;
        }
        $timelog_file = $timelog_dir->file($timelog_file);
        $timelog_file->openw->close;
        my @format = map { "\%$_" } qw/C e U S I K P/;
        $line = qq|/usr/bin/time -o '$timelog_file' -a -f "@format" $line|;
    }

    return $line;
}


END {
    # The Test::Harness is hacked-up a bit already, so we're just controlling
    # the command which goes into it an parsing output.
    if ($timelog_dir) {
        $timelog_sum->openw->print(
            sort
            map { $_->openr->getlines }
            $timelog_dir->children
        );
        if (-z $timelog_sum) {
            unlink $timelog_sum;
            warn "Error producing time summary file!";
        }
        $timelog_dir->rmtree;
    }
}

1;

=pod

=head1 NAME

B<runtests> - run one or more GSC test scripts

=head1 SYNOPSIS

 # run everything
 cd my_sandbox/GSC
 runtests -I .. --db production --no-commit --long

 # run only selected tests
 cd my_sandbox/GSC
 runtests -I .. --db production --no-commit t/sometest.t t/anothertest.t

 # run only tests which load the GSC::DNA module
 cd my_sandbox/GSC
 runtests -I .. --db production --no-commit --cover GSC/DNA.pm

 # run only tests which cover the changes you have in subversion
 cd my_sandbox/GSC
 runtests -I .. --db production --no-commit --cover-svn-changes


=head1 DESCRIPTION

Runtests is a GSC-build test harness, similar to "prove".  When run w/o
parameters, it looks for "t" directory in the current working directory,
and runs ALL tests under that directory.

This script should be run before committing changes to svn/cvs.

=head1 OPTIONS

=over 4

=item --no-commit

 Like all App-based programs at the GSC, this allows the user to disable DBI
 commits on the subclassed handles used by the GSC OO API.

 Tests should be run against production with --no-commit before deploying code.

=item --db [production|development]

 Like all App-based programs at the GSC, this allows the user to specify which
 database set should be used for the tests.

 Tests should be run against production with --no-commit before deploying code.

=item --long

 Include "long" tests, which are otherwise skipped in test harness execution

=item -v

 Be verbose, meaning that individual cases will appear instead of just a full-script summary

=item --cover My/Module.pm

 Looks in a special sqlite database which is updated by the cron which runs tests,
 to find all tests which load My/Module.pm at some point before they exit.  Only
 these tests will be run.

* you will still need the --long flag to run long tests.

* if you specify tests on the command-line, only tests in both lists will run

* this can be specified multiple times

=item --cover-TOOL-changes

 TOOL can be svn, svk, or cvs.

 The script will run either "svn status", "svk status", or "cvs -q up" on a parent
 directory with "GSC" in it, and get all of the changes in your perl_modules trunk.
 It will behave as though those modules were listed as individual --cover options.

=head1 BUGS

This currently has a lot hard-coded to the GSC schema.  The UR tree's
"ur test run" module will replace this with a namespace-independent version.

=over 4

=back

Report bugs to <software@watson.wustl.edu>.

=cut


